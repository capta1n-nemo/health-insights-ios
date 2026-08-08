import Foundation

/// **One vocabulary for "a thing that happens to a person".**
///
/// This app grew two of them independently. `EventCause` (15 cases, with
/// display names, question phrasings and symbols) is what a flagged heart event
/// offers the reader. `TagApplicability` (11 cases) is what a tag imported from
/// Oura gets filed under. They describe the same universe at different
/// granularities, and until 2026-08-09 **no code converted between them** —
/// nine of the eleven tag categories have a direct `EventCause` counterpart and
/// nothing said so.
///
/// The reader found it from the outside, which is the only way this kind of
/// thing gets found:
///
/// > *"a tag called 'Sex' came in from Oura, and while I know we have 'sexual
/// > activity' as an option in flagged events, I couldn't link it as sexual
/// > activity."*
///
/// They were right, and it failed four times over: the tag classifier's output
/// type could not hold the concept, no `TagApplicability` case covered it, no
/// stem matched it, and the on-device model had no legal token to emit.
/// `docs/tag-mapping-research-2026-08-07.md` §7 had already named the fix —
/// *"one taxonomy with a stated mapping rather than two taxonomies pretending
/// to be one"* — and then the shipped code went the other way.
///
/// So this is the taxonomy, and the other two are **views of it**:
///
/// - `applicability` is the coarse grouping the Tags page shows. Total, so a
///   concept can never be unfileable.
/// - `eventCause` is the flagged-event answer, and is **`nil` for the four
///   concepts a heart-rate spike cannot plausibly be about**. That nil is the
///   honest half of the mapping: "rest" is a real thing to log and not a real
///   answer to *"your heart rate rose for half an hour — what were you doing?"*
///
/// ⚠️ **Adding a case here adds something the reader can *tell* the app.** It is
/// not a finding and never a detection — the same warning `EventCause` carries.
public enum MomentConcept: String, Sendable, Codable, CaseIterable, Identifiable, Hashable {
    case exercise
    /// Deliberate recovery — a nap, a sauna, a rest day. Distinct from
    /// `poorSleep`, which is a complaint about the night rather than a choice.
    case rest
    case poorSleep
    case stress
    case excitement
    /// How the reader felt, where that is the whole of what they logged.
    case mood
    case feelingUnwell
    case socialising
    case intimacy
    case caffeine
    case alcohol
    case nicotine
    case otherSubstance
    case medication
    case nutrition
    case travel
    case work

    public var id: String { rawValue }

    /// **The stated mapping onto the coarse tag grouping.** Total on purpose:
    /// every concept has a home, so nothing can fall through to
    /// `.unclassified` by omission. `.unclassified` remains what a *classifier*
    /// returns when it could not place a word — never what this mapping returns.
    public var applicability: TagApplicability {
        switch self {
        case .exercise: return .activity
        case .rest, .poorSleep: return .sleepRecovery
        case .stress, .excitement, .mood: return .mentalHealth
        case .feelingUnwell: return .illness
        case .socialising, .intimacy: return .social
        case .caffeine, .alcohol, .nicotine, .otherSubstance: return .substances
        case .medication: return .medication
        case .nutrition: return .nutrition
        case .travel: return .travel
        case .work: return .work
        }
    }

    /// The flagged-event answer this concept is, where it is one.
    ///
    /// ⚠️ **`nil` is a statement, not a gap.** A flag says the reader's heart
    /// rate rose for half an hour with almost no steps under it. "I had a nap",
    /// "I ate", "I was at work" and "my mood was low" are things worth logging
    /// and are not answers to that question — offering them would pad the list
    /// with options that cannot explain the thing being asked about.
    public var eventCause: EventCause? {
        switch self {
        case .exercise: return .exercise
        case .intimacy: return .intimacy
        case .stress: return .stress
        case .excitement: return .excitement
        case .socialising: return .socialising
        case .caffeine: return .caffeine
        case .alcohol: return .alcohol
        case .nicotine: return .nicotine
        case .otherSubstance: return .otherSubstance
        case .medication: return .medication
        case .feelingUnwell: return .feelingUnwell
        case .poorSleep: return .poorSleep
        case .travel: return .travel
        case .rest, .mood, .nutrition, .work: return nil
        }
    }

    /// The reader-facing name. Where a concept is also an `EventCause` the two
    /// **must** read identically — a reader who answered "Sexual activity" on a
    /// flagged event and then sees "Intimacy" on a tag has met two words for one
    /// thing, which is the confusion this type exists to end.
    public var displayName: String {
        if let cause = eventCause { return cause.displayName }
        switch self {
        case .rest: return "Rest or a nap"
        case .mood: return "Mood"
        case .nutrition: return "Food or drink"
        case .work: return "Work or study"
        default: return rawValue
        }
    }

    public var symbolName: String {
        if let cause = eventCause { return cause.symbolName }
        switch self {
        case .rest: return "zzz"
        case .mood: return "face.smiling"
        case .nutrition: return "fork.knife"
        case .work: return "briefcase"
        default: return "questionmark.circle"
        }
    }

    /// Concepts a classifier may choose from, in the order a picker shows them.
    /// All of them — unlike `TagApplicability.classifiable`, there is no
    /// "unplaced" case here, because *not placing something* is the absence of a
    /// concept rather than a concept of its own.
    public static var pickable: [MomentConcept] { allCases }

    /// Every concept that maps onto this coarse grouping. The inverse of
    /// `applicability`, derived rather than written down, so the two can never
    /// disagree.
    public static func concepts(in applicability: TagApplicability) -> [MomentConcept] {
        allCases.filter { $0.applicability == applicability }
    }
}

public extension EventCause {
    /// The shared concept this answer is, where it is one.
    ///
    /// `nil` for `somethingElse` and `nothingNotable`, which are answers *about
    /// the question* rather than things that happened — "I don't want to say"
    /// and "your flag was wrong". Neither is a concept a tag could ever be
    /// about, and both must stay reachable on a flagged event.
    var concept: MomentConcept? {
        switch self {
        case .exercise: return .exercise
        case .intimacy: return .intimacy
        case .stress: return .stress
        case .excitement: return .excitement
        case .socialising: return .socialising
        case .caffeine: return .caffeine
        case .alcohol: return .alcohol
        case .nicotine: return .nicotine
        case .otherSubstance: return .otherSubstance
        case .medication: return .medication
        case .feelingUnwell: return .feelingUnwell
        case .poorSleep: return .poorSleep
        case .travel: return .travel
        case .somethingElse, .nothingNotable: return nil
        }
    }
}
