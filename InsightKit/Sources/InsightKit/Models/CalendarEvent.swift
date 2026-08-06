import Foundation

/// **An event from the reader's own calendar.**
///
/// Backlog I1, the reader's instruction: *"Calendar — sync one or many Apple
/// calendars, and unsync, under Integrations like the others."* It is the single
/// highest-leverage unbuilt thing in the app, because it is the only blocker on
/// **two** cards the reader has asked for by name — travel drain (#15) and work
/// impact (#16) — and neither can be built without it.
///
/// ## Why this is a type in InsightKit rather than an `EventKit` value
///
/// `EventKit` does not exist on Linux, and InsightKit is where every model, test
/// and card lives. A card that reads the calendar must be testable without a
/// device, so the app target does the fetching and hands over these — the same
/// division `HealthMetricSample` already draws against HealthKit.
///
/// ## ⚠️ It reads the event's content, and that reverses an earlier decision
///
/// The first version of this type stored **no title, no location and no notes**,
/// on the grounds that a calendar names people, addresses and appointments,
/// this repo is public, and the two cards it was built for needed only *when*
/// and *where in the world*. A test asserted the absence, precisely so that
/// widening it would have to be a decision somebody took rather than a struct
/// drifting.
///
/// **That decision was taken, by the reader, hours later** (2026-08-06): *"I
/// want it to use AI to read the meetings and their content, and actually rank
/// each calendar item."* So the content is read — and the rule that actually
/// mattered is unchanged and now stated where it belongs:
///
/// 1. **Content is read and classified entirely on the device.** There is no
///    network path out of this app in this build. ⚠️ **It is no longer true
///    that content can never leave** — backlog B8 R5, at the reader's explicit
///    instruction, added a two-tier sharing preference in which `SharingTier.full`
///    would include a corrected event's title and location, and both tiers
///    default to on. Nothing is transmitted today (no endpoint exists), and
///    `SharingTier.metadataOnly` never carries a word of it. The honest claim is
///    *"classification is on-device, and what may ever be shared is stated in
///    Settings ▸ Data & model improvement"* — not *"it never leaves"*.
/// 2. **A title, a location or a note must never reach a doc, a commit message,
///    a test fixture or a log line.** `docs/privacy-and-ip.md`'s rule is the
///    shape of a finding, never the reading — and an event title is the most
///    identifying string this app will ever hold. That rule is unchanged by B8:
///    a sharing tier the reader can see and switch off is a different thing from
///    a value pasted into a public repository.
/// 3. **Notes are still not stored, and neither is the guest list.** The reader
///    asked for six specific judgements and none of them needs the body of an
///    event or the names of the people in it; *derived* values carry the
///    questions instead — `hasVideoLink` for "did it include a remote meeting
///    link", `organizerIsReader` for "did I organise this", and `attendeeCount`
///    for how many were in the room.
///
/// The test that guarded the old rule now guards this one.
public struct CalendarEvent: Sendable, Equatable, Identifiable, Hashable, Codable {
    /// A stable identifier from the calendar store, so re-syncing updates rather
    /// than duplicates.
    public let id: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    /// The IANA identifier of the event's own time zone, when it carries one.
    ///
    /// **The reason travel drain needs this file at all.** The app captures no
    /// HealthKit metadata, so no sample knows what time zone it was recorded in;
    /// a calendar event does, and a change in it between one day and the next is
    /// the cleanest signal of a flight the phone can give without asking for
    /// location.
    public let timeZoneIdentifier: String?
    /// Which of the reader's calendars it came from — the *calendar's* name, not
    /// the event's. "Work", "Family", "Travel" is exactly the axis the work-impact
    /// card needs, and it remains the single strongest signal for work-versus-
    /// personal even now that the title is available.
    public let calendarName: String
    public let kind: Kind

    // MARK: Content — read on device, never exported. See the type's own note.

    /// The event's title.
    public let title: String
    /// Where it said to be, when it said anywhere. **The presence signal**: an
    /// event with a place is one the reader had to physically attend.
    public let location: String?
    /// Whether a video-conference link was attached — derived in the app target
    /// from the location, URL and notes, so the *fact* of a link is kept and the
    /// link itself is not.
    public let hasVideoLink: Bool
    /// Whether the event's organiser is the reader — derived in the app target
    /// from EventKit's own `isCurrentUser` and from `ReaderIdentity`'s email
    /// list, so the *fact* is kept and the organiser's address is not. The same
    /// shape as `hasVideoLink`, for the same reason: the question ("did I
    /// organise this, or just attend?" — the reader, B7 H1) is a boolean, and
    /// the address behind it is one more identifying string not to hold.
    ///
    /// `nil` means the event carries no organiser at all — the shape of an
    /// event the reader created in their own calendar — which is *unknown*,
    /// not "not the reader". `CalendarEventClassifier` treats the three states
    /// differently and says why.
    public let organizerIsReader: Bool?

    /// **How many people were invited — never who.** The third value in the
    /// same family as `hasVideoLink` and `organizerIsReader`: the app-side fetch
    /// reads `EKEvent.attendees`, keeps the count, and drops the list before it
    /// is ever stored.
    ///
    /// It is here for backlog B8 R3 — the correction record's artifact snapshot
    /// names it, because a correction on an event whose size is unknown teaches
    /// less than one on an event that had twelve people in it. `nil` means the
    /// event carried no attendee information at all, which is the ordinary shape
    /// of something the reader put in their own calendar; it is *unknown*, not
    /// zero.
    ///
    /// ⚠️ **This deliberately widens a type whose narrowness was tested.**
    /// `CalendarModelTests.testTheEventStoresNoNotesAndNoAttendees` asserts the
    /// exact field set precisely so that growth is a decision somebody took. The
    /// decision: a *count* is not a guest list, and the ban that mattered — the
    /// names and addresses of other people — is unchanged and still asserted.
    public let attendeeCount: Int?

    /// A coarse shape, decided by the app rather than by the event's words.
    public enum Kind: String, Sendable, Codable, CaseIterable {
        /// A normal timed event.
        case timed
        /// All-day, which is usually a marker rather than a commitment.
        case allDay
        /// Multi-day and all-day — the shape a holiday or a trip takes.
        case multiDay

        public var title: String {
            switch self {
            case .timed: return "Timed"
            case .allDay: return "All day"
            case .multiDay: return "Spanning days"
            }
        }
    }

    public init(id: String, start: Date, end: Date, isAllDay: Bool,
                timeZoneIdentifier: String?, calendarName: String, kind: Kind,
                title: String = "", location: String? = nil,
                hasVideoLink: Bool = false, organizerIsReader: Bool? = nil,
                attendeeCount: Int? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarName = calendarName
        self.kind = kind
        self.title = title
        self.location = location
        self.hasVideoLink = hasVideoLink
        self.organizerIsReader = organizerIsReader
        self.attendeeCount = attendeeCount
    }

    public var durationHours: Double {
        max(0, end.timeIntervalSince(start)) / 3600
    }
}

/// Reading a calendar as a shape of days.
///
/// Deliberately thin for now: this is the *plumbing* the two requested cards
/// need, and building their arithmetic before their input exists is the failure
/// mode this repo records three times. What is here is what a card can be built
/// on immediately — and, crucially, what can be tested on Linux.
public enum CalendarModel {

    /// Hours committed on a given local day, from timed events only.
    ///
    /// All-day events are excluded rather than counted as 24 hours: a birthday
    /// marker is not a day of work, and treating it as one would make every
    /// calendar look uniformly full.
    public static func committedHours(_ events: [CalendarEvent], on day: Date,
                                      calendar: Calendar = .current) -> Double {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return events
            .filter { $0.kind == .timed && $0.start < end && $0.end > start }
            .reduce(0) { total, event in
                // Clipped to the day, so a meeting spanning midnight is not
                // counted twice or attributed wholly to one side of it.
                let from = max(event.start, start)
                let to = min(event.end, end)
                return total + max(0, to.timeIntervalSince(from)) / 3600
            }
    }

    /// Days on which the calendar's time zone differs from the one before it —
    /// **the travel signal**, and the whole reason `timeZoneIdentifier` is
    /// stored.
    ///
    /// Returns the day of each change together with the zone moved to. Nothing
    /// here claims a flight: a reader who set one event in another zone by hand
    /// produces the same shape, and a card built on this has to say so.
    public static func timeZoneChanges(_ events: [CalendarEvent],
                                       calendar: Calendar = .current)
        -> [(day: Date, zone: String)] {
        let dated = events
            .compactMap { event -> (Date, String)? in
                guard let zone = event.timeZoneIdentifier else { return nil }
                return (calendar.startOfDay(for: event.start), zone)
            }
            .sorted { $0.0 < $1.0 }
        var out: [(day: Date, zone: String)] = []
        var previous: String?
        for (day, zone) in dated where zone != previous {
            if previous != nil { out.append((day, zone)) }
            previous = zone
        }
        return out
    }

    /// The busiest stretch, for a card that wants to name one.
    public static func busiestDay(_ events: [CalendarEvent],
                                  within days: Int = 28,
                                  now: Date = Date(),
                                  calendar: Calendar = .current) -> (day: Date, hours: Double)? {
        let start = calendar.date(byAdding: .day, value: -days,
                                  to: calendar.startOfDay(for: now)) ?? now
        var best: (Date, Double)?
        for offset in 0...days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let hours = committedHours(events, on: day, calendar: calendar)
            if hours > (best?.1 ?? 0) { best = (day, hours) }
        }
        return best.map { (day: $0.0, hours: $0.1) }
    }
}
