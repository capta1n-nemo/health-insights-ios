import Foundation

/// **Something happened, and the app noticed but does not know what it was.**
///
/// Backlog P32, in the reader's own words: the app flags an event — *"heart rate
/// spiked 30 mins this evening — sexual activity?"* — and they confirm or
/// correct it, with a *"GPS map, time, why it was flagged"*.
///
/// ## The line this type is built along
///
/// A flagged event is **a measurement plus a question**, and the two must never
/// be allowed to blur. `evidence` is measured: a heart rate ran high for a
/// stretch, that far above this person's own typical level for that time of day,
/// with that little movement to explain it. `candidates` is a *guess list*, and
/// most of the time it is a bad one — the app has no instrument that can tell
/// arousal from anxiety from an argument from a cold coming on. Physiology does
/// not carry that label, and no amount of modelling puts it there.
///
/// So this type keeps them in separate fields with separate wording, the feed
/// asks rather than asserts, and `FlaggedEventJudgement` files the reader's
/// answer somewhere the guess cannot reach — which is what makes the guess's
/// accuracy measurable instead of self-congratulatory. That discipline is
/// `CalendarEventJudgement`'s, copied deliberately.
///
/// ## What it is not
///
/// **Not a diagnosis, and not evidence about anybody's body.** A flag says a
/// number moved. The reader's answer says what they were doing. Nothing here
/// ever infers the second from the first, and the same caution that governs
/// `SickDayLedger` applies with more force: the causes below include ones a
/// person may not wish to be wrong about.
public struct FlaggedEvent: Sendable, Equatable, Codable, Identifiable {

    /// Stable across re-detection, so a reader's answer stays attached when the
    /// detector runs again over the same history. Derived from the window's
    /// start and the trigger — the two things that do not move — rather than a
    /// UUID, which would mint a new event every launch and re-ask every
    /// question.
    public let id: String

    /// The window the elevation covered.
    public let start: Date
    public let end: Date

    /// What fired.
    public let trigger: FlagTrigger

    /// The numbers, and only the numbers.
    public let evidence: FlagEvidence

    /// Where, at the coarsest resolution that still answers the question.
    /// **Never an input to `candidates`** — see `PlaceContext` and
    /// `CauseCandidate.Basis`.
    public let place: PlaceContext

    /// What it could have been, best first. May be empty when the detector has
    /// nothing at all to offer, which is an honest state and not a bug.
    public let candidates: [CauseCandidate]

    /// The detector that produced this, so a judgement made against version 1
    /// is not silently counted as evidence about version 2.
    public let modelVersion: String

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var minutes: Int { Int((duration / 60).rounded()) }

    /// **The guess accuracy is measured against**: the top candidate, whatever
    /// its weight.
    ///
    /// ⚠️ **Deliberately not gated on confidence.** An earlier draft returned
    /// nil below a margin, so the app only ever "guessed" when the substance log
    /// had already told it the answer — which would have made the accuracy
    /// figure a measure of the substance log rather than of the ranking, and the
    /// ranking is the thing the reader's corrections are supposed to teach.
    /// A weak guess offered honestly and scored honestly is the learning loop
    /// they asked for; a guess withheld to protect a statistic is not.
    ///
    /// The honesty lives in the *presentation* instead: the feed says "could
    /// this have been…", prints `guessBasis` beside it, and lists the
    /// alternatives at the same size.
    public var guess: EventCause? { candidates.first?.cause }

    /// How the top candidate was arrived at — the sentence that stops a coin
    /// flip reading like a finding.
    public var guessBasis: CauseCandidate.Basis? { candidates.first?.basis }

    public init(id: String, start: Date, end: Date, trigger: FlagTrigger,
                evidence: FlagEvidence, place: PlaceContext = .unobserved,
                candidates: [CauseCandidate] = [],
                modelVersion: String = FlaggedEventDetector.modelVersion) {
        self.id = id
        self.start = start
        self.end = end
        self.trigger = trigger
        self.evidence = evidence
        self.place = place
        self.candidates = candidates
        self.modelVersion = modelVersion
    }

    /// The same event with the position forgotten. Called on review and by
    /// `FlaggedEventRetention` — see `PlaceContext.forgettingCoordinate()`.
    public func forgettingCoordinate() -> FlaggedEvent {
        FlaggedEvent(id: id, start: start, end: end, trigger: trigger,
                     evidence: evidence, place: place.forgettingCoordinate(),
                     candidates: candidates, modelVersion: modelVersion)
    }

    /// The same event carrying a place. Detection and location capture happen at
    /// different times and on different threads, so they are joined rather than
    /// computed together.
    public func at(_ place: PlaceContext) -> FlaggedEvent {
        FlaggedEvent(id: id, start: start, end: end, trigger: trigger,
                     evidence: evidence, place: place,
                     candidates: candidates, modelVersion: modelVersion)
    }

    /// The question the feed asks. **A question, never a statement** — the
    /// wording is the honesty control for a guess the app cannot support.
    public var question: String {
        guard let guess, guess != .somethingElse, guess != .nothingNotable else {
            return "What were you doing?"
        }
        return "Was this \(guess.inQuestion)?"
    }

    /// The headline the row carries — measured only.
    public var headline: String { trigger.headline(minutes: minutes) }
}

/// What set an event off. One measured pattern each; nothing here is a cause.
public enum FlagTrigger: String, Sendable, Codable, CaseIterable, Hashable {
    /// A stretch of heart rate above this person's own typical level for that
    /// part of the day, **with too little movement to account for it**. The one
    /// trigger this detector implements today.
    case restingHeartRateElevation

    /// A stretch of elevation during the hours the reader is usually asleep.
    ///
    /// ⚠️ **Declared, not implemented.** Separating it from the case above needs
    /// a sleep window, and reading one honestly means going through the sleep
    /// pipeline rather than assuming midnight-to-six. Listed here so the day it
    /// is built it lands as a case rather than as a second detector — and so the
    /// enum is the record that the distinction was seen rather than missed.
    case nocturnalHeartRateElevation

    public var displayName: String {
        switch self {
        case .restingHeartRateElevation: return "Heart rate up at rest"
        case .nocturnalHeartRateElevation: return "Heart rate up overnight"
        }
    }

    func headline(minutes: Int) -> String {
        let span = minutes == 1 ? "a minute" : "\(minutes) minutes"
        switch self {
        case .restingHeartRateElevation:
            return "Your heart rate ran high for \(span), and you weren't moving"
        case .nocturnalHeartRateElevation:
            return "Your heart rate ran high for \(span) overnight"
        }
    }
}

/// **The measured half.** Every field here came off an instrument or out of
/// arithmetic on one; nothing in it is a guess.
public struct FlagEvidence: Sendable, Equatable, Codable, Hashable {
    /// The highest reading inside the window, in the metric's canonical unit.
    public let peak: Double
    /// This person's own typical level for this part of the day, over
    /// `referenceDays` of their own history.
    public let typical: Double
    /// Their own typical *variation* around that, robustly estimated (median
    /// absolute deviation, scaled). The denominator of `departures`.
    public let spread: Double
    /// How many of their own typical variations the peak sat above typical.
    public let departures: Double
    /// How many days of history the reference was built from. **Printed**, so a
    /// departure computed against a fortnight is never mistaken for one computed
    /// against a season.
    public let referenceDays: Int
    /// Steps recorded across the window. The reason the app can say "and you
    /// weren't moving" rather than merely "your heart rate was up".
    public let stepsInWindow: Double?
    /// How many readings the window contains. A stretch built from two samples
    /// is a different claim from one built from twenty.
    public let sampleCount: Int

    public init(peak: Double, typical: Double, spread: Double,
                referenceDays: Int, stepsInWindow: Double?, sampleCount: Int) {
        self.peak = peak
        self.typical = typical
        self.spread = spread
        self.referenceDays = referenceDays
        self.stepsInWindow = stepsInWindow
        self.sampleCount = sampleCount
        self.departures = spread > 0 ? (peak - typical) / spread : 0
    }

    /// Why it was flagged, in the reader's terms — the third of the three things
    /// P32 asks the card to carry.
    ///
    /// **Stated with its uncertainty**, per the standing rule: the reference
    /// window is named, the spread is described as the reader's own variation
    /// rather than as a statistical term, and the movement clause only appears
    /// when there is a step figure to back it.
    public var sentence: String {
        var out = String(format: "Peaked at %.0f against your usual %.0f for this time of day — %.1f× your own normal variation, measured over the last %d days.",
                         peak, typical, departures, referenceDays)
        if let steps = stepsInWindow {
            out += steps < 1
                ? " No steps recorded in that window."
                : String(format: " Only %.0f steps in that window.", steps)
        }
        return out
    }
}

/// **What an event could have been.** The reader's own vocabulary, not a
/// clinical one.
///
/// ⚠️ **These are answer options, not findings.** The list exists so the reader
/// has something to tap; the app's own guess at which one applies is weak by
/// construction and the feed says so. Adding a case is adding a thing the reader
/// can *tell* the app, which is why `somethingElse` and `nothingNotable` are
/// both here: "I don't want to say" and "nothing happened" are real answers and
/// an option list without them forces a false one.
public enum EventCause: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    case exercise
    case intimacy
    case stress
    case excitement
    case socialising
    case caffeine
    case alcohol
    case nicotine
    case otherSubstance
    case medication
    case feelingUnwell
    case poorSleep
    case travel
    /// Something the app has no case for. **Kept alongside a free-text note** on
    /// the judgement, so a reader whose answer is not on the list is not forced
    /// to pick a wrong one — and so the notes accumulate into evidence about
    /// which case is missing.
    case somethingElse
    /// The flag was wrong: nothing was going on. **A label, not an absence** —
    /// the same distinction `CalendarEventJudgement.isConfirmed` draws, and for
    /// the same reason: a false positive the reader took the trouble to mark is
    /// the most useful correction in the set, and treating it as "unanswered"
    /// would throw it away.
    case nothingNotable

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .exercise: return "Exercise or exertion"
        case .intimacy: return "Sexual activity"
        case .stress: return "Stress or anxiety"
        case .excitement: return "Excitement"
        case .socialising: return "Socialising"
        case .caffeine: return "Caffeine"
        case .alcohol: return "Alcohol"
        case .nicotine: return "Nicotine"
        case .otherSubstance: return "Another substance"
        case .medication: return "Medication"
        case .feelingUnwell: return "Feeling unwell"
        case .poorSleep: return "Bad night's sleep"
        case .travel: return "Travelling"
        case .somethingElse: return "Something else"
        case .nothingNotable: return "Nothing — this one's wrong"
        }
    }

    /// The phrase that fits inside "Was this …?".
    var inQuestion: String {
        switch self {
        case .exercise: return "exercise"
        case .intimacy: return "sexual activity"
        case .stress: return "stress"
        case .excitement: return "excitement"
        case .socialising: return "you socialising"
        case .caffeine: return "caffeine"
        case .alcohol: return "alcohol"
        case .nicotine: return "nicotine"
        case .otherSubstance: return "something you took"
        case .medication: return "your medication"
        case .feelingUnwell: return "you feeling unwell"
        case .poorSleep: return "a bad night"
        case .travel: return "travelling"
        case .somethingElse: return "something else"
        case .nothingNotable: return "nothing"
        }
    }

    public var symbolName: String {
        switch self {
        case .exercise: return "figure.run"
        case .intimacy: return "heart"
        case .stress: return "exclamationmark.triangle"
        case .excitement: return "sparkles"
        case .socialising: return "person.2"
        case .caffeine: return "cup.and.saucer"
        case .alcohol: return "wineglass"
        case .nicotine: return "smoke"
        case .otherSubstance: return "pills"
        case .medication: return "cross.vial"
        case .feelingUnwell: return "thermometer.medium"
        case .poorSleep: return "bed.double"
        case .travel: return "airplane"
        case .somethingElse: return "questionmark.circle"
        case .nothingNotable: return "xmark.circle"
        }
    }

    /// The substance classes that map onto a cause, so a logged event can raise
    /// the right option rather than a generic one.
    static func from(_ substance: SubstanceClass) -> EventCause {
        switch substance {
        case .caffeine: return .caffeine
        case .alcohol: return .alcohol
        case .nicotine: return .nicotine
        case .stimulant, .mdma, .cannabis, .psychedelic, .dissociative,
             .depressant, .other:
            return .otherSubstance
        }
    }
}

/// One option on the list, with **how it got there**.
public struct CauseCandidate: Sendable, Equatable, Codable, Hashable, Identifiable {

    /// ⚠️ **The field that keeps this list honest.** Two candidates can sit next
    /// to each other with similar weights and mean entirely different things:
    /// one because the reader logged a double espresso forty minutes earlier,
    /// the other because it was a Tuesday evening. Printing the basis beside the
    /// option is what stops the second reading like the first.
    public enum Basis: String, Sendable, Codable, CaseIterable, Hashable {
        /// The reader themselves recorded something that overlaps the window —
        /// a substance, a dose. The only basis in this enum resting on data.
        case loggedByYou
        /// A movement signal in the window supports it.
        case measuredMovement
        /// **A prior about the time of day, and nothing more.** Weak, and the
        /// feed must say so out loud.
        case timeOfDay
        /// Offered on every event so the list is never a forced choice.
        case alwaysOffered

        /// The clause the feed prints under the option.
        public var sentence: String {
            switch self {
            case .loggedByYou: return "You logged something around then"
            case .measuredMovement: return "Movement in that window"
            case .timeOfDay: return "A guess from the time of day — nothing measured says so"
            case .alwaysOffered: return "Always an option"
            }
        }

        /// Whether anything measured supports it. Drives the feed's wording and
        /// nothing else — the ranking must not quietly promote on this, or the
        /// basis stops being an independent statement about the ranking.
        public var isEvidenceBacked: Bool {
            switch self {
            case .loggedByYou, .measuredMovement: return true
            case .timeOfDay, .alwaysOffered: return false
            }
        }
    }

    public let cause: EventCause
    /// 0–1, the sort key. **Not a probability** and never printed as a
    /// percentage: there is no calibration set behind it, and dressing an
    /// ordering heuristic as a likelihood is exactly what this app does not do.
    public let weight: Double
    public let basis: Basis
    /// The specific reason, where there is one worth naming ("you logged alcohol
    /// 50 minutes before").
    public let why: String?

    public var id: String { cause.rawValue }

    public init(cause: EventCause, weight: Double, basis: Basis, why: String? = nil) {
        self.cause = cause
        self.weight = weight
        self.basis = basis
        self.why = why
    }
}

/// **The event exactly as it stood when it was flagged.**
///
/// The third layer `CalendarEventJudgement` learnt to keep (backlog B8 R3), for
/// the same reason: a guess and a correction alone make a *tally* — the app can
/// say it was wrong fourteen times and nothing about what it was wrong at. The
/// snapshot is what turns a count into a training pair.
///
/// ⚠️ **The place is stored as a familiarity only.** A snapshot is the one
/// structure that would otherwise accumulate coordinates indefinitely — it is
/// kept forever by design, which is precisely the shape `PlaceContext` refuses
/// to hold a position in. So the artifact carries the comparison and never the
/// cell.
public struct FlaggedEventArtifact: Sendable, Equatable, Codable, Hashable {
    public let start: Date
    public let end: Date
    public let trigger: FlagTrigger
    public let evidence: FlagEvidence
    public let placeFamiliarity: PlaceFamiliarity
    public let candidates: [CauseCandidate]
    public let modelVersion: String

    public init(_ event: FlaggedEvent) {
        self.start = event.start
        self.end = event.end
        self.trigger = event.trigger
        self.evidence = event.evidence
        self.placeFamiliarity = event.place.familiarity
        self.candidates = event.candidates
        self.modelVersion = event.modelVersion
    }

    public init(start: Date, end: Date, trigger: FlagTrigger,
                evidence: FlagEvidence, placeFamiliarity: PlaceFamiliarity,
                candidates: [CauseCandidate], modelVersion: String) {
        self.start = start
        self.end = end
        self.trigger = trigger
        self.evidence = evidence
        self.placeFamiliarity = placeFamiliarity
        self.candidates = candidates
        self.modelVersion = modelVersion
    }

    /// Whether the event as it stands now differs from the one that was judged.
    /// Re-detection can move a window's edges as more samples arrive, and a
    /// reader's answer about a fifteen-minute stretch is not automatically an
    /// answer about the fifty-minute one it grew into.
    public func differs(from event: FlaggedEvent) -> Bool {
        start != event.start || end != event.end
            || trigger != event.trigger
            || evidence != event.evidence
            || modelVersion != event.modelVersion
    }
}
