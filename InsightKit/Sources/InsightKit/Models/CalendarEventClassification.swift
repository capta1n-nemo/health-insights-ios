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
        /// **A sick day** — §B11-6, the reader's own words: the classifier
        /// *"must be able to classify a day as 'sick', in the same dropdown as
        /// meeting, reminder, travel"*.
        ///
        /// Its own case rather than a flavour of `.leave`, and the difference is
        /// not cosmetic: a holiday is recovery the reader chose and a sick day
        /// is the opposite, so folding them together would let a week of flu
        /// reset `daysSinceLastLeave` and read as rest. It feeds `SickDayLedger`
        /// exactly as `.leave` feeds `HolidayLedger`, and nothing else.
        ///
        /// ⚠️ **The two axes that stop applying.** Work-versus-personal and
        /// formality are meaningless for a sick day — there is no meeting to be
        /// formal about and being ill is not a work event — so the review row
        /// hides both and offers `severity` instead. The stored values are still
        /// there (a correction *away* from `.sick` must not have silently lost
        /// them), they are simply not asked about.
        case sick
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .meeting: return "Meeting"
            case .reminder: return "Reminder"
            case .blockedTime: return "Blocked time"
            case .travel: return "Travel"
            case .leave: return "Your leave"
            case .absence: return "Someone away"
            case .sick: return "Sick day"
            }
        }
        /// Whether work/personal and formality are worth asking about.
        ///
        /// One property rather than two `if occasion == .sick` tests in the
        /// review row, so the next occasion that stops caring about them says so
        /// here instead of in a view.
        public var asksAboutWorkAndFormality: Bool { self != .sick }
    }

    /// **How ill the reader was**, on the one axis a sick day has — §B11-6:
    /// *"It does need a severity of sickness selector."*
    ///
    /// Three grades and an unstated, deliberately mirroring `SymptomSeverity`'s
    /// vocabulary rather than inventing a second scale: the reader already grades
    /// symptoms mild/moderate/severe in Apple Health, and two scales for the same
    /// idea is how a reconciliation stops being possible. **Not a number** — a
    /// 1–10 would invite arithmetic on a word somebody chose.
    ///
    /// `unstated` is the honest default for a sick day the *rules* found in a
    /// calendar: the title said the reader was ill, and said nothing about how
    /// badly. Only the reader fills this in.
    public enum SickSeverity: String, Sendable, Codable, CaseIterable, Identifiable {
        case unstated, mild, moderate, severe
        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .unstated: return "Not said"
            case .mild: return "Mild"
            case .moderate: return "Moderate"
            case .severe: return "Severe"
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

    /// **How ill, on a sick day** — nil on every other occasion, and nil on a
    /// sick day nobody has graded yet.
    ///
    /// Optional rather than defaulted to `.unstated` for the reason
    /// `SymptomSeverity.notPresent` is not a Bool: "the reader said mild" and
    /// "nobody has said" are different records, and a non-optional would erase
    /// the second. Synthesised `Codable` decodes an absent optional as nil, so
    /// every judgement stored before §B11-6 reads back unchanged.
    public let severity: SickSeverity?

    public init(context: Context, occasion: Occasion, presence: Presence,
                formality: Formality, hours: Double,
                deciders: [String: Decider] = [:],
                severity: SickSeverity? = nil) {
        self.context = context
        self.occasion = occasion
        self.presence = presence
        self.formality = formality
        self.hours = hours
        self.deciders = deciders
        // A severity on anything but a sick day is a category error, and the
        // one place it could arrive from is a draft the reader edited *before*
        // moving the occasion back. Dropped here rather than in the view, so
        // no caller can store one.
        self.severity = occasion == .sick ? severity : nil
    }

    public static let contextKey = "context"
    public static let occasionKey = "occasion"
    public static let formalityKey = "formality"
    public static let severityKey = "severity"

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
        // own leave feeds the *holiday ledger* (B7 H5/H6), never the meeting
        // load.
        //
        // ⚠️ **H2's open half, ruled on with H6 (2026-08-08): a colleague's OOO
        // is zero and never negative.** The brief hedged it — *"possibly
        // reduced load (fewer meetings that week)"* — and the hedge was right to
        // be a hedge. Three reasons, and the first alone settles it:
        //
        // 1. **The reduction is already in the calendar.** A colleague who is
        //    away does not attend, so their meetings are cancelled or declined
        //    and simply are not there to be counted. Subtracting hours for the
        //    absence would remove the same meetings twice — once by their not
        //    existing, once by a constant — and the card would report a quiet
        //    week that was quiet only in arithmetic.
        // 2. **The sign is not even known.** Somebody's absence raises the
        //    reader's load as often as it lowers it: cover, handover, the thing
        //    that waited. A constant would have to pick a direction the app
        //    cannot see.
        // 3. **There is nothing to size it against.** Work impact scores
        //    exposure against the reader's own spread of working-day load, and a
        //    negative term for an absence would be a number invented here
        //    wearing calendar clothes — the refusal `docs/norms-and-telemetry.md`
        //    describes, one level down.
        //
        // So the honest floor is the honest answer, and it is no longer
        // provisional.
        case .leave, .absence: return 0
        // A sick day is not a commitment either, and it is emphatically not
        // load: the reader was not working. Zero for the same reason leave is
        // zero — and note that the *cost* of being ill is the symptom radar's
        // subject, not this card's.
        case .sick: return 0
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

/// One event, its classification, any correction the reader has made, **and the
/// artifact the app judged.**
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
///
/// ## Three layers, not two (backlog B8 R3)
///
/// Guess and correction alone make a **tally**: the app can say it was wrong
/// fourteen times and nothing more, because whatever it was wrong *about* is not
/// in the record. `artifact` is the third layer — a snapshot of the event as it
/// stood at classification time — and it is what turns a count into a training
/// pair. The reader asked for exactly this: *"we remember the 'AI Estimated' and
/// 'Corrected' data points, in addition to the whole email/artifact."*
public struct CalendarEventJudgement: Sendable, Equatable, Codable, Identifiable {
    public let eventID: String
    /// What the app worked out, untouched by any correction.
    public let classification: CalendarEventClassification
    /// What the reader said, where they said anything.
    public let correction: CalendarEventClassification?
    /// **The event as it was when `classification` was made.** Optional because
    /// rows written before B8 R3 have no snapshot and are not going to grow one
    /// retrospectively — inventing it from today's event is precisely the
    /// history-rewrite the snapshot exists to prevent.
    public let artifact: CalendarEventArtifact?
    /// True where the reader looked at it and agreed. **Different from an
    /// absent correction** — "confirmed correct" is a label and "not yet looked
    /// at" is not, and treating them as one would inflate any accuracy figure
    /// the app ever computes.
    public let isConfirmed: Bool
    public let reviewedAt: Date?
    /// **When the event was first seen to have changed after the reader had
    /// already answered about it**, and nil while it has not.
    ///
    /// ⚠️ **The one thing a re-judgement is not allowed to resolve.** Re-running
    /// the classifier refreshes the guess *and* the snapshot — it has to, or the
    /// stored pair stops being a real training example — and the moment the
    /// snapshot moves, the comparison that found the drift stops reporting it.
    /// The reader's correction would then sit there looking current, when it was
    /// actually an answer about a version of the event that no longer exists.
    ///
    /// So the fact is recorded separately from the comparison and outlives it.
    /// Backlog C4 keeps the guess and the reader's answer apart so accuracy stays
    /// measurable; this keeps them apart in *time* as well — where the two may
    /// have come apart, the reader is told rather than overruled. Cleared only by
    /// the reader looking again (`reviewed(correction:confirmed:at:)`).
    public let changedAfterReviewAt: Date?

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
            // §B11-6. A reader who agreed it was a sick day and said *how ill*
            // has still told the app something it did not know, and a
            // `wasCorrected` that could not see it would count that as the
            // model having been right about a field it never guessed.
            || correction.severity != classification.severity
    }

    /// Whether the reader answered about a version of this event that no longer
    /// exists. **Surfaced, never resolved** — see `changedAfterReviewAt`.
    ///
    /// Gated on there being an answer at all: an untouched guess cannot have
    /// gone stale, it can only be re-judged, which is exactly what happens to it.
    public var needsRereview: Bool {
        changedAfterReviewAt != nil && (isConfirmed || correction != nil)
    }

    /// Whether the event as it stands now differs from the one that was judged.
    ///
    /// False when there is no snapshot: a row written before B8 R3 has nothing to
    /// compare against, and "changed" would be an invention — the same refusal
    /// the artifact itself makes about a start it never recorded.
    public func hasDrifted(from event: CalendarEvent) -> Bool {
        artifact?.differs(from: event) ?? false
    }

    /// Note that the event moved under a reader who had already answered.
    ///
    /// Idempotent and **earliest-wins**: the instant worth keeping is when their
    /// answer first went stale, not the last time a sync happened to notice. A
    /// judgement nobody has reviewed is returned unchanged — there is no answer
    /// for the change to have invalidated.
    public func markedChangedAfterReview(at date: Date) -> CalendarEventJudgement {
        guard reviewedAt != nil, changedAfterReviewAt == nil else { return self }
        return CalendarEventJudgement(eventID: eventID,
                                      classification: classification,
                                      correction: correction,
                                      isConfirmed: isConfirmed,
                                      reviewedAt: reviewedAt,
                                      artifact: artifact,
                                      changedAfterReviewAt: date)
    }

    public init(eventID: String, classification: CalendarEventClassification,
                correction: CalendarEventClassification? = nil,
                isConfirmed: Bool = false, reviewedAt: Date? = nil,
                artifact: CalendarEventArtifact? = nil,
                changedAfterReviewAt: Date? = nil) {
        self.eventID = eventID
        self.classification = classification
        self.correction = correction
        self.isConfirmed = isConfirmed
        self.reviewedAt = reviewedAt
        self.artifact = artifact
        self.changedAfterReviewAt = changedAfterReviewAt
    }

    /// **Re-classification, as a rule rather than a habit.**
    ///
    /// Running the classifier again — a new model version, a reader identity
    /// entered late — must replace the guess and leave everything the reader
    /// said exactly where it was. That was true of `DataStore.recordClassification`
    /// by construction (the write path never had the correction in hand), and it
    /// was true only there: nothing stated it as a value-level invariant and
    /// nothing tested it. This is the invariant, and the store now mirrors it.
    ///
    /// The artifact moves **with the guess**, not with the correction: the pair
    /// (what was read, what was concluded) has to stay self-consistent or the
    /// training example is a fiction. Passing `nil` keeps whatever snapshot is
    /// already stored rather than erasing it, so a re-classification with no
    /// event in hand degrades to the old two-layer record instead of losing the
    /// third.
    ///
    /// ⚠️ **`changedAfterReviewAt` survives too**, and that is the point of it
    /// being stored rather than derived: this call is what refreshes the
    /// snapshot, so the drift comparison goes quiet a line later. If the flag
    /// moved with the snapshot, a re-judgement would silently decide that a
    /// correction made about the old event still describes the new one.
    public func reclassified(as classification: CalendarEventClassification,
                             artifact: CalendarEventArtifact? = nil) -> CalendarEventJudgement {
        CalendarEventJudgement(eventID: eventID,
                               classification: classification,
                               correction: correction,
                               isConfirmed: isConfirmed,
                               reviewedAt: reviewedAt,
                               artifact: artifact ?? self.artifact,
                               changedAfterReviewAt: changedAfterReviewAt)
    }

    /// The reader's answer, recorded against the guess that is already stored.
    ///
    /// The counterpart to `reclassified`: it moves the correction and touches
    /// neither the guess nor the artifact. ⚠️ **The snapshot is deliberately not
    /// refreshed here** — the model judged a particular version of the event, and
    /// re-reading it at correction time would attribute words to the model that
    /// it may never have seen.
    ///
    /// ⚠️ **It clears `changedAfterReviewAt`**, and only this does. The reader is
    /// looking at the event as it stands now, so whatever it did since they last
    /// answered has been answered for.
    public func reviewed(correction: CalendarEventClassification?,
                         confirmed: Bool, at date: Date) -> CalendarEventJudgement {
        CalendarEventJudgement(eventID: eventID,
                               classification: classification,
                               correction: correction,
                               isConfirmed: confirmed,
                               reviewedAt: date,
                               artifact: artifact,
                               changedAfterReviewAt: nil)
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
