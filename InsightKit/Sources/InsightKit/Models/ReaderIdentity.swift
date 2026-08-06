import Foundation

/// **Who the reader is, to their own calendar** — backlog B7 H1, and the
/// reader's request verbatim: *"maybe I can input my name to give context to
/// the events (e.g. did i organise the meeting, or did i just attend) and if it
/// is something like a 'John smith on holiday - OOO' It can see if that is me,
/// or someone else. I could also be asked input my emails, as input data, like
/// my work email … and personal emails."*
///
/// ## Why this is not part of `UserHealthProfile`
///
/// The profile's grounding inputs are **numeric by construction** —
/// `GroundingInput` carries a `Double`, because everything the clinical models
/// ask for is a number. A name and a list of email addresses are strings, and
/// widening the grounding pipeline to carry them would loosen the type that
/// every scoring model reads for the benefit of the one consumer that does not
/// score. So identity is its own value, stored beside the profile rather than
/// inside it.
///
/// ## ⚠️ Privacy: the most identifying value the reader can hand over
///
/// A name and an email address identify the reader outright, and this repo is
/// public. The rules, in force here and at every consumer:
///
/// 1. **The value stays on the phone.** It is a JSON file in Application
///    Support, read by the classifier, and it is **never exported** — the
///    export's own keys are the proof (`HealthDataExport` carries no identity).
/// 2. **No real name or address ever appears in a test fixture, a doc, a
///    commit message or a log line.** Fixtures use obviously fake values
///    ("a.reader@example.com"), per `docs/privacy-and-ip.md`.
///
/// ## What it buys
///
/// - **Whose OOO block is that** — H2. A name match in the title, or the
///   organiser matching one of these emails, makes an absence *the reader's
///   leave*; a mismatch makes it someone else's; no identity at all makes it
///   ambiguous, and an ambiguous absence is never counted as a work meeting.
/// - **Organiser-versus-attendee**, once the app-side fetch compares the
///   event's organiser against these addresses (`CalendarEvent.organizerIsReader`).
public struct ReaderIdentity: Sendable, Codable, Equatable {

    /// The reader's display name, as they would write it — "Jane Reader".
    /// Optional: emails alone still answer the organiser question.
    public var name: String?
    /// Work addresses. Kept apart from personal ones because the *kind* of
    /// address that organised an event is itself context — a meeting organised
    /// from a work address is a work meeting whatever its title says. (No
    /// consumer draws that inference yet; the split is stored so the one that
    /// does will not need a migration.)
    public var workEmails: [String]
    public var personalEmails: [String]

    public init(name: String? = nil, workEmails: [String] = [],
                personalEmails: [String] = []) {
        self.name = name
        self.workEmails = workEmails
        self.personalEmails = personalEmails
    }

    /// Whether the reader has said anything at all. The classifier treats an
    /// unconfigured identity exactly like no identity — a blank name must not
    /// make every unnamed OOO block read as "not mine".
    public var isConfigured: Bool {
        !(name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !allEmails.isEmpty
    }

    /// Every address, work and personal, normalised and de-blanked.
    public var allEmails: [String] {
        (workEmails + personalEmails)
            .map(Self.normalizedEmail)
            .filter { !$0.isEmpty }
    }

    // MARK: - Matching

    /// Case-insensitive, trimmed, and tolerant of the `mailto:` prefix EventKit
    /// puts on an organiser's URL — the shape this is actually called with.
    static func normalizedEmail(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("mailto:") { value = String(value.dropFirst("mailto:".count)) }
        return value
    }

    /// Whether an organiser string — an address, or EventKit's `mailto:` URL —
    /// is one of the reader's own addresses.
    public func matches(organizer: String?) -> Bool {
        guard let organizer else { return false }
        let candidate = Self.normalizedEmail(organizer)
        guard !candidate.isEmpty else { return false }
        return allEmails.contains(candidate)
    }

    /// Whether a piece of text — in practice an event title — names the reader.
    ///
    /// **Word-boundary, order-free**: every word of the name must appear as a
    /// whole word, so "John Smith" is found in "Smith, John — OOO" and is *not*
    /// found in "Johnson Smithers offsite". Order-free because calendars write
    /// names both ways round; whole-word because a substring match would find
    /// "Ann" inside "Annual leave", which is precisely the kind of false
    /// positive that would turn a colleague's marker into the reader's holiday.
    ///
    /// A single-word name is honoured but is weak evidence, and the doc says so
    /// rather than pretending otherwise: "Jo" as a name matches any title with
    /// the word "jo" in it. The classifier only consults this for titles that
    /// already read as an absence, which bounds the damage.
    public func isMe(_ text: String) -> Bool {
        let nameTokens = Self.words(in: name ?? "")
        guard !nameTokens.isEmpty else { return false }
        let textTokens = Set(Self.words(in: text))
        return nameTokens.allSatisfy { textTokens.contains($0) }
    }

    /// Lower-cased words, split on anything that is not a letter or a digit —
    /// so punctuation, dashes and possessives all act as boundaries.
    static func words(in text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
