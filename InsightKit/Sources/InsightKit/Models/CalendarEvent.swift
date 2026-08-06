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
/// ## ⚠️ What is deliberately not stored
///
/// **No title, no notes, no attendees, no location.** A calendar is the most
/// revealing thing on a phone — it names people, addresses, appointments and
/// diagnoses — and this repo is public. What the two cards that motivated it
/// actually need is *when the reader was busy, where in the world they were, and
/// how the day was shaped*. None of that requires knowing what the meeting was
/// called.
///
/// So this carries times, a coarse `kind`, and the event's own time zone. If a
/// future card genuinely needs a title, that is a decision to take deliberately
/// and to write down — not something to widen this struct into by habit.
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
    /// card needs and carries none of the event's own content.
    public let calendarName: String
    public let kind: Kind

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
                timeZoneIdentifier: String?, calendarName: String, kind: Kind) {
        self.id = id
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendarName = calendarName
        self.kind = kind
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
