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

    private static func matches(_ text: String, _ words: [String]) -> Bool {
        let lower = text.lowercased()
        return words.contains { lower.contains($0) }
    }

    // MARK: - Classify

    /// Everything the rules can decide. The model refines `context` and
    /// `formality` afterwards where it is available and confident.
    public static func classify(_ event: CalendarEvent) -> CalendarEventClassification {
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
        // Travel first: a multi-day all-day event called "Sydney" is a trip, and
        // the reader said they use placeholders exactly like that. Checked ahead
        // of `reminder` because "flight" beats every other reading of a title.
        let occasion: CalendarEventClassification.Occasion
        if matches(title, travelWords) || (event.kind == .multiDay && !matches(title, reminderWords)) {
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

    // MARK: - What the cards read

    /// The three data sources the reader named — *"Work Events, Personal Events,
    /// Travel Events"* — derived rather than stored, so a correction changes
    /// which bucket an event is in with no migration.
    public static func bucket(_ judgements: [CalendarEventJudgement],
                              events: [CalendarEvent]) -> [CalendarEventBucket: [CalendarEvent]] {
        let byID = Dictionary(uniqueKeysWithValues: judgements.map { ($0.eventID, $0.effective) })
        var out: [CalendarEventBucket: [CalendarEvent]] = [:]
        for event in events {
            let classification = byID[event.id] ?? classify(event)
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
    public init(_ classification: CalendarEventClassification) {
        if classification.occasion == .travel { self = .travel; return }
        switch classification.context {
        case .work: self = .work
        case .personal: self = .personal
        case .unknown: self = .other
        }
    }
}
