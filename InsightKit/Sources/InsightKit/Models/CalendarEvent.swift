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
/// 1. **Content is read on the device and never leaves it.** Classification runs
///    against Apple's on-device model; there is no network path.
/// 2. **A title, a location or a note must never reach a doc, a commit message,
///    a test fixture, a log line or an export.** `docs/privacy-and-ip.md`'s rule
///    is the shape of a finding, never the reading — and an event title is the
///    most identifying string this app will ever hold.
/// 3. **Notes are still not stored.** The reader asked for six specific
///    judgements and none of them needs the body of an event; a *derived
///    boolean* — `hasVideoLink` — carries what "did it include a remote meeting
///    link" actually asks, without keeping the link.
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
                hasVideoLink: Bool = false) {
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
