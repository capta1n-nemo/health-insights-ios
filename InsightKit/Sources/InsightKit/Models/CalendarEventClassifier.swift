import Foundation

/// **The deterministic half of reading a calendar** — everything that can be
/// decided exactly, decided exactly.
///
/// The reader asked for AI to read their events, and it does. This is what runs
/// *first*, and what runs *instead* when the on-device model is unavailable —
/// which is most hardware, and every test.
///
/// ## What it answers on its own, and what it hands over
///
/// | Axis | Here | Why |
/// | --- | --- | --- |
/// | Duration, marathon | ✅ exact | arithmetic |
/// | Presence (in person / remote) | ✅ exact | a field is present or it is not |
/// | Occasion — travel | ✅ mostly | the reader's own placeholders are formulaic |
/// | Occasion — reminder vs meeting | ✅ mostly | all-day with no place and no link is not a meeting |
/// | Occasion — whose absence (OOO) | ✅ with identity | name/organiser match; ambiguous is never a meeting |
/// | Work vs personal | ◐ calendar name first | the model settles an ambiguous title |
/// | Formality / sentiment | ◐ keywords | genuinely interpretive; the model is better |
///
/// **The two `◐` rows are what the model is asked about**, and only those. Asking
/// it about duration would be slower, non-deterministic and less accurate than
/// subtraction — and would put a hallucination between the reader and a fact
/// their own calendar already stated.
///
/// ⚠️ **Every keyword list here is a guess about one person's habits**, which is
/// exactly why the reader can correct any of it and why corrections are stored
/// separately from guesses. These are a starting point that gets measured, not a
/// claim about what words mean.
public enum CalendarEventClassifier {

    /// A single stretch at or beyond this is a day, not a slot.
    public static let marathonHours: Double = 4
    /// Reviewed events needed before an accuracy figure is offered.
    public static let minimumReviewedForAccuracy = 10

    // MARK: - The word lists
    //
    // Lower-cased, matched as substrings on a lower-cased title. Substrings
    // rather than tokens on purpose: "1:1" and "catch-up" do not tokenise the
    // way a reader writes them.

    static let travelWords = [
        "flight", "fly ", "flying", "airport", "depart", "arrive", "landing",
        "boarding", "travel", "trip to", "drive to", "train to", "transfer",
        "check-in", "checkin", "layover", "overseas", "domestic",
    ]
    static let reminderWords = [
        "birthday", "anniversary", "bin day", "rubbish", "renew", "expires",
        "due", "reminder", "pay ", "book ", "order ", "collect",
    ]
    static let blockedTimeWords = [
        "focus", "deep work", "admin", "lunch", "gym", "workout", "run",
        "training", "no meetings", "blocked", "prep", "hold",
    ]
    static let formalWords = [
        "client", "board", "interview", "review", "presentation", "pitch",
        "qbr", "steering", "committee", "audit", "appraisal", "performance",
        "stakeholder", "exec", "quarterly",
    ]
    static let casualWords = [
        "catch up", "catchup", "coffee", "chat", "1:1", "1-1", "one to one",
        "standup", "stand-up", "sync", "hello", "welcome", "social", "drinks",
        "lunch", "walk",
    ]
    static let workWords = [
        "standup", "sprint", "retro", "client", "project", "deadline",
        "review", "roadmap", "planning", "sync", "1:1", "team", "board",
        "interview", "demo", "release", "qbr",
    ]
    static let personalWords = [
        "dentist", "doctor", "gp ", "school", "birthday", "holiday", "haircut",
        "vet", "family", "mum", "dad", "anniversary", "wedding", "party",
    ]
    static let personalCalendarNames = [
        "personal", "family", "home", "birthdays", "holidays", "us", "private",
    ]
    static let workCalendarNames = ["work", "office", "business"]

    // MARK: The leave vocabulary — word-boundary matched, unlike everything above
    //
    // B7 H2. These are matched as *whole words and phrases*, not substrings,
    // because the stakes are different: a substance word misread costs one
    // event's formality, but "leave" found inside "Leavers' drinks" would file
    // a party into the holiday ledger. Normalisation (below) lower-cases and
    // turns every non-alphanumeric into a space, so "out-of-office", "Out of
    // Office" and "OOO!" all match.

    /// Absence markers — the workplace convention for *a person being away*.
    /// Kept apart from `leaveVocabulary` because an OOO that carries extra
    /// words usually carries the absent person's **name** ("Sarah OOO"),
    /// which is evidence about ownership the destination-shaped words below
    /// do not give ("Holiday to Sydney" names a place, not a person).
    static let absenceMarkers = ["ooo", "out of office"]
    /// Leave in the reader's own words: "annual leave", "vacation", "PTO",
    /// "holiday". These usually mark the *reader's* time off and often carry a
    /// destination. Bare "leave" is deliberately **not** here — it is the one
    /// word of the brief's vocabulary that doubles as a verb ("Leave for
    /// airport"), so it gets its own weaker rung below.
    static let leaveVocabulary = [
        "annual leave", "on leave", "vacation", "pto", "holiday", "holidays",
    ]
    /// Words that make a leave-vocabulary title an *event* rather than an
    /// absence — the edge the reader's brief demands judgement on: "Holiday
    /// party" is a party. A veto list rather than cleverness, because these
    /// words are doing one job: they say people are gathering.
    static let eventfulWords = [
        "party", "parties", "dinner", "drinks", "lunch", "brunch", "breakfast",
        "concert", "market", "sale", "shopping", "festival", "fair", "gala",
        "quiz", "celebration", "gift", "gifts", "card", "cards",
    ]
    /// Connective tissue that appears *inside* leave phrases and their
    /// grammar. Used only by the who-is-named check: a token outside this set,
    /// the leave vocabulary and the reader's own name is treated as naming
    /// somebody (or something) else.
    static let leaveConnectors: Set<String> = [
        "on", "of", "out", "office", "the", "a", "an", "is", "am", "away",
        "day", "days", "today", "until", "till", "from", "to", "back", "off",
        "for", "in", "at",
    ]

    private static func matches(_ text: String, _ words: [String]) -> Bool {
        let lower = text.lowercased()
        return words.contains { lower.contains($0) }
    }

    /// The whole title as space-separated word tokens, padded, so a phrase
    /// wrapped in spaces can only match on word boundaries.
    private static func normalized(_ text: String) -> String {
        " " + ReaderIdentity.words(in: text).joined(separator: " ") + " "
    }

    private static func containsPhrase(_ text: String, _ phrases: [String]) -> Bool {
        let padded = normalized(text)
        return phrases.contains { padded.contains(" \($0) ") }
    }

    // MARK: - Whose absence is this (H2)

    /// Reads a title as an absence, or refuses to.
    ///
    /// Returns `.leave` (the reader's own — feeds H3/H5), `.absence` (someone
    /// else's, or unresolvable), or nil (not an absence at all). The decision
    /// ladder, most reliable evidence first:
    ///
    /// 1. **No leave vocabulary, or an eventful word** → not an absence.
    ///    "Holiday party" has a leave word *and* a gathering word, and the
    ///    gathering word wins — it is a thing the reader attends.
    /// 2. **The title names the reader** (`ReaderIdentity.isMe`) → their leave.
    ///    "John Smith on holiday — OOO" is mine when I am John Smith.
    /// 3. **The organiser fact** (`organizerIsReader`, derived on-device from
    ///    EventKit) → mine when true, someone else's when false.
    /// 4. **No identity configured** → ambiguous, and ambiguous is `.absence`:
    ///    the one hard rule from the brief is that an unowned OOO block is
    ///    *never* a work meeting, and without identity "mine" cannot be said.
    /// 5. **An absence marker with unexplained words** → someone else's.
    ///    "Sarah OOO" carries a token that is not vocabulary, not grammar and
    ///    not the reader — in practice, the absent colleague's name.
    /// 6. **Otherwise** → the reader's own. A bare "OOO", "Annual leave" or
    ///    "Holiday to Sydney" in the reader's own calendar is theirs: other
    ///    people's absences arrive named (rule 5) or organised by them (rule
    ///    3), and a destination is not a person. The known residual — "<name>
    ///    annual leave" for a name the identity does not hold — misfiles as
    ///    the reader's, and the review sheet is the backstop: correcting
    ///    `.leave` to `.absence` is one tap and is never overwritten.
    static func absenceOccasion(for event: CalendarEvent,
                                identity: ReaderIdentity?)
        -> (occasion: CalendarEventClassification.Occasion,
            decider: CalendarEventClassification.Decider)? {
        let title = event.title
        let isMarked = containsPhrase(title, absenceMarkers)
        let saysLeave = containsPhrase(title, leaveVocabulary)
        // Bare "leave" is the weakest rung: a verb as often as a noun. It only
        // counts when nothing about the title reads as a departure — "Leave
        // for airport" belongs to the travel rule, not the holiday ledger.
        let bareLeave = containsPhrase(title, ["leave"])
            && !matches(title, travelWords)
        guard isMarked || saysLeave || bareLeave else { return nil }
        guard !containsPhrase(title, eventfulWords) else { return nil }

        // An unconfigured identity is no identity — a blank name must not turn
        // every unnamed OOO into "not mine".
        let identity = identity?.isConfigured == true ? identity : nil

        if let identity, identity.isMe(title) { return (.leave, .rules) }
        if let organised = event.organizerIsReader {
            // Read off the event, not judged — the one rung that is a fact.
            return (organised ? .leave : .absence, .fact)
        }
        guard let identity else { return (.absence, .rules) }

        if isMarked {
            let known = Set(absenceMarkers.flatMap { $0.split(separator: " ").map(String.init) })
                .union(leaveVocabulary.flatMap { $0.split(separator: " ").map(String.init) })
                .union(leaveConnectors)
                .union(ReaderIdentity.words(in: identity.name ?? ""))
            let unexplained = ReaderIdentity.words(in: title).contains { token in
                token.count > 1 && !token.allSatisfy(\.isNumber) && !known.contains(token)
            }
            if unexplained { return (.absence, .rules) }
        }
        return (.leave, .rules)
    }

    // MARK: - Classify

    /// Everything the rules can decide. The model refines `context` and
    /// `formality` afterwards where it is available and confident.
    ///
    /// `identity` is who the reader said they are (B7 H1), consulted for one
    /// question only: **whose absence an OOO-shaped block records.** Optional
    /// with a nil default because every axis but that one is decidable without
    /// it — and because a classifier that demanded identity before reading a
    /// calendar would block the whole feature on a Settings screen.
    public static func classify(_ event: CalendarEvent,
                                identity: ReaderIdentity? = nil)
        -> CalendarEventClassification {
        let title = event.title
        var deciders: [String: CalendarEventClassification.Decider] = [:]

        // MARK: presence — a fact, not a judgement
        let hasPlace = !(event.location ?? "").trimmingCharacters(in: .whitespaces).isEmpty
        let presence: CalendarEventClassification.Presence
        switch (hasPlace, event.hasVideoLink) {
        case (true, true): presence = .hybrid
        case (true, false): presence = .inPerson
        case (false, true): presence = .remote
        case (false, false): presence = .unstated
        }

        // MARK: occasion
        //
        // Absence first — before travel, deliberately. The old travel rule
        // claims every multi-day block that isn't a reminder, and a multi-day
        // "Annual leave" *is* travel-shaped; but the reader's brief is explicit
        // that an OOO-shaped block is someone's absence before it is anything
        // else, and only the absence reading can answer "whose". Travel words
        // in a leave title ("Leave for airport") lose here too, and that is the
        // acceptable cost of never counting a holiday as a commute.
        let occasion: CalendarEventClassification.Occasion
        if let absence = absenceOccasion(for: event, identity: identity) {
            occasion = absence.occasion
            deciders[CalendarEventClassification.occasionKey] = absence.decider
        } else if matches(title, travelWords) || (event.kind == .multiDay && !matches(title, reminderWords)) {
            occasion = .travel
            deciders[CalendarEventClassification.occasionKey] = .rules
        } else if matches(title, reminderWords)
                    || (event.isAllDay && !hasPlace && !event.hasVideoLink) {
            // **An all-day entry with nowhere to be and nobody to dial is not a
            // meeting.** That single rule catches most of what the reader means
            // by "just something like a reminder", without reading a word.
            occasion = .reminder
            deciders[CalendarEventClassification.occasionKey] = event.isAllDay ? .fact : .rules
        } else if matches(title, blockedTimeWords) {
            occasion = .blockedTime
            deciders[CalendarEventClassification.occasionKey] = .rules
        } else {
            occasion = .meeting
            deciders[CalendarEventClassification.occasionKey] = .rules
        }

        // MARK: work or personal
        //
        // The calendar's own name is the strongest signal there is and beats any
        // reading of a title — someone who keeps a "Work" calendar has already
        // done the classification by hand, every time, for years.
        let context: CalendarEventClassification.Context
        if matches(event.calendarName, workCalendarNames) {
            context = .work
            deciders[CalendarEventClassification.contextKey] = .fact
        } else if matches(event.calendarName, personalCalendarNames) {
            context = .personal
            deciders[CalendarEventClassification.contextKey] = .fact
        } else if matches(title, workWords) {
            context = .work
            deciders[CalendarEventClassification.contextKey] = .rules
        } else if matches(title, personalWords) {
            context = .personal
            deciders[CalendarEventClassification.contextKey] = .rules
        } else {
            // Left open on purpose — this is one of the two axes the model is
            // asked about, and a rules-based guess here would be a coin toss
            // wearing a confident label.
            context = .unknown
            deciders[CalendarEventClassification.contextKey] = .rules
        }

        // MARK: formality
        let formality: CalendarEventClassification.Formality
        if matches(title, formalWords) {
            formality = .formal
            deciders[CalendarEventClassification.formalityKey] = .rules
        } else if matches(title, casualWords) {
            formality = .casual
            deciders[CalendarEventClassification.formalityKey] = .rules
        } else {
            formality = .standard
            deciders[CalendarEventClassification.formalityKey] = .rules
        }

        return CalendarEventClassification(
            context: context, occasion: occasion, presence: presence,
            formality: formality, hours: event.durationHours, deciders: deciders)
    }

    /// Fold the on-device model's reading into a rules classification.
    ///
    /// ⚠️ **The model may only move the two interpretive axes.** It is not
    /// allowed near duration, presence or a context the *calendar's own name*
    /// already settled — those are facts, and a language model overruling a fact
    /// is the failure this split exists to prevent.
    public static func refined(_ base: CalendarEventClassification,
                               modelContext: CalendarEventClassification.Context?,
                               modelFormality: CalendarEventClassification.Formality?)
        -> CalendarEventClassification {
        var deciders = base.deciders
        var context = base.context
        var formality = base.formality

        // A context the calendar's own name settled is a fact and stands.
        if base.decider(for: CalendarEventClassification.contextKey) != .fact,
           let modelContext, modelContext != .unknown {
            context = modelContext
            deciders[CalendarEventClassification.contextKey] = .model
        }
        if let modelFormality {
            formality = modelFormality
            deciders[CalendarEventClassification.formalityKey] = .model
        }
        return CalendarEventClassification(
            context: context, occasion: base.occasion, presence: base.presence,
            formality: formality, hours: base.hours, deciders: deciders)
    }

    /// Re-read one stored guess against a changed identity, touching **only the
    /// occasion**.
    ///
    /// When the reader enters their name or emails (H1), every OOO-shaped block
    /// already classified deserves a second look — an "Annual leave" the app
    /// filed as travel last week is their leave now that it can say so. But the
    /// stored classification may carry a context or formality the on-device
    /// *model* decided, and re-running the plain rules over everything would
    /// silently demote those. So this moves the one axis identity informs and
    /// preserves every other axis and its decider. Returns nil when the
    /// occasion would not change, so callers can skip the write.
    ///
    /// Corrections are untouched by construction: this produces a
    /// *classification*, and `CalendarEventJudgement` keeps the reader's
    /// correction beside it, always winning.
    public static func reoccasioned(_ stored: CalendarEventClassification,
                                    for event: CalendarEvent,
                                    identity: ReaderIdentity?)
        -> CalendarEventClassification? {
        let fresh = classify(event, identity: identity)
        guard fresh.occasion != stored.occasion else { return nil }
        var deciders = stored.deciders
        deciders[CalendarEventClassification.occasionKey] =
            fresh.decider(for: CalendarEventClassification.occasionKey)
        return CalendarEventClassification(
            context: stored.context, occasion: fresh.occasion,
            presence: stored.presence, formality: stored.formality,
            hours: stored.hours, deciders: deciders)
    }

    // MARK: - Drift: the event changed after it was judged

    /// **Which of these events no longer match the snapshot they were judged
    /// against**, in the order they were given.
    ///
    /// A pure comparison — no rules, no model, one dictionary lookup per event —
    /// which is what makes it safe on every sync. Re-judging what it returns is a
    /// separate and deliberately debounced step; see
    /// `AppModel.flushCalendarReclassification()`.
    ///
    /// Two things it deliberately does not call drift:
    ///
    /// - **An event with no judgement.** That is unjudged, not changed, and the
    ///   sync path already classifies those.
    /// - **A judgement written before the artifact snapshot existed.** There is
    ///   nothing to compare, and treating "cannot tell" as "changed" would spend
    ///   the on-device model on every pre-B8 row at once, which is precisely the
    ///   *"do not completely slow down the app"* half of the reader's
    ///   instruction.
    public static func drifted(_ judgements: [CalendarEventJudgement],
                               events: [CalendarEvent]) -> [CalendarEvent] {
        let byID = Dictionary(judgements.map { ($0.eventID, $0) },
                              uniquingKeysWith: { first, _ in first })
        return events.filter { byID[$0.id]?.hasDrifted(from: $0) == true }
    }

    // MARK: - What the cards read

    /// The three data sources the reader named — *"Work Events, Personal Events,
    /// Travel Events"* — derived rather than stored, so a correction changes
    /// which bucket an event is in with no migration.
    ///
    /// `identity` reaches the classify fallback for events not yet judged, so a
    /// colleague's OOO cannot land in the work bucket while its judgement is
    /// still being written.
    public static func bucket(_ judgements: [CalendarEventJudgement],
                              events: [CalendarEvent],
                              identity: ReaderIdentity? = nil) -> [CalendarEventBucket: [CalendarEvent]] {
        let byID = Dictionary(uniqueKeysWithValues: judgements.map { ($0.eventID, $0.effective) })
        var out: [CalendarEventBucket: [CalendarEvent]] = [:]
        for event in events {
            let classification = byID[event.id] ?? classify(event, identity: identity)
            out[CalendarEventBucket(classification), default: []].append(event)
        }
        return out
    }
}

/// The named categories the reader asked to see as data sources.
public enum CalendarEventBucket: String, Sendable, CaseIterable, Identifiable, Hashable {
    case work, personal, travel, other
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .work: return "Work events"
        case .personal: return "Personal events"
        case .travel: return "Travel events"
        case .other: return "Other events"
        }
    }

    /// **Travel outranks work and personal**, because a flight booked in a work
    /// calendar is still travel — and travel is the axis one of the two
    /// requested cards is entirely about.
    ///
    /// **An absence outranks the calendar it sits in**, for the same reason
    /// (B7 H2): a holiday booked in a work calendar is still the reader's own
    /// life, so `.leave` files as personal — the brief's one hard rule is that
    /// it must never count as work. `.absence` files as other, because whose
    /// it is was precisely what could not be established, and either named
    /// bucket would be a claim nobody made. Deliberately *not* new bucket
    /// cases — the backlog: "a new classification outcome, not a new bucket
    /// bolted on".
    public init(_ classification: CalendarEventClassification) {
        switch classification.occasion {
        case .travel: self = .travel; return
        case .leave: self = .personal; return
        case .absence: self = .other; return
        case .meeting, .reminder, .blockedTime: break
        }
        switch classification.context {
        case .work: self = .work
        case .personal: self = .personal
        case .unknown: self = .other
        }
    }
}
