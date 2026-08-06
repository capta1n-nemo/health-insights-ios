import Foundation
import EventKit
import InsightKit

/// **The reader's calendars, as a data source.**
///
/// Backlog I1, and their instruction verbatim: *"Calendar — sync one or many
/// Apple calendars, and unsync, under Integrations like the others."*
///
/// It is listed beside Oura and Withings for the reason `ShotsyIntegration`
/// already is: from the reader's side "where does my data come from" has one
/// answer, and this is where that answer lives — even though the mechanism is
/// on-device permission rather than OAuth.
///
/// ## Why it matters more than its size suggests
///
/// It is the **only** blocker on two cards the reader has asked for by name:
/// travel drain (#15) and work impact (#16). Neither can be built without it,
/// and the original plan for travel drain assumed the phone already knew what
/// time zone a reading was taken in. It does not — the app captures no HealthKit
/// metadata at all — so a calendar event's own time zone is the cleanest signal
/// of a flight available without asking for location.
///
/// ## ⚠️ What it reads, and what it refuses to keep
///
/// It reads titles and locations, because the reader asked for the events to be
/// classified (2026-08-06) and six of their six questions need the words. See
/// `CalendarEvent` for the reversal and its reasoning.
///
/// **Notes and the guest list are read once, here, and never stored.** What is
/// taken from them is two numbers and a boolean: was a video-conference link
/// attached (the question the reader asked — "did it include a remote meeting
/// link" — where the URL answers nothing further), and **how many people were
/// invited**, which B8 R3's correction artifact names and which says nothing
/// about who they were. This function is the only place in the app where an
/// event's notes or attendee records exist at all, and they do not outlive the
/// loop.
///
/// The reader picks which calendars to include and that choice is persisted, so
/// "sync my work calendar and not my family one" is one tap rather than an
/// all-or-nothing permission.
@MainActor
final class CalendarIntegration: HealthIntegration {

    let id = "calendar"
    let displayName = "Calendar"
    let iconSystemName = "calendar"

    /// It contributes no `MetricType` at all, and that is honest rather than a
    /// gap: a meeting is not a measurement. `IntegrationCapabilities` has no way
    /// to say "brings events", so it says nothing rather than claiming a metric
    /// it does not produce.
    let capabilities = IntegrationCapabilities(metrics: [], requiresBackend: false)

    /// How far back a sync reaches. A year, because the cards this feeds compare
    /// a recent stretch against a season.
    static let lookbackDays = 365
    /// And a little ahead, so "you have a heavy week coming" is possible without
    /// a second fetch.
    static let lookaheadDays = 14

    private let store = EKEventStore()
    private let defaults: UserDefaults

    /// Which calendar identifiers the reader chose. Empty means *all of them*,
    /// which is the right default for someone who has just granted access and
    /// has not been asked to choose yet.
    private static let selectionKey = "calendar.selectedIdentifiers"
    private static let lastSyncKey = "calendar.lastSync"
    /// Set once the reader connects, so a revoked-then-restored permission does
    /// not silently re-enable a source they turned off.
    private static let connectedKey = "calendar.connected"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Status

    var status: IntegrationStatus {
        guard defaults.bool(forKey: Self.connectedKey) else { return .notConnected }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return .connected(lastSync: defaults.object(forKey: Self.lastSyncKey) as? Date)
        case .denied, .restricted:
            return .unavailable(reason: "Calendar access is off for this app. Settings ▸ Privacy & Security ▸ Calendars.")
        case .writeOnly:
            // A real state and a confusing one: the app can add events and not
            // read them, which is the opposite of what it wants.
            return .unavailable(reason: "This app has write-only calendar access, so it cannot read your events. Grant full access in Settings ▸ Privacy & Security ▸ Calendars.")
        case .notDetermined:
            return .notConnected
        @unknown default:
            return .notConnected
        }
    }

    // MARK: - Connect

    func connect() async throws {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            throw NSError(domain: "calendar", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Calendar access was not granted."])
        }
        defaults.set(true, forKey: Self.connectedKey)
    }

    func disconnect() async {
        // The permission itself belongs to iOS and only the reader can revoke
        // it in Settings — so "disconnect" here means *stop reading*, and it
        // says so rather than implying the app has torn something down it
        // cannot. The stored events are cleared by the caller.
        defaults.set(false, forKey: Self.connectedKey)
        defaults.removeObject(forKey: Self.lastSyncKey)
        defaults.removeObject(forKey: Self.selectionKey)
    }

    // MARK: - Which calendars

    /// Every calendar the reader could include, for the picker.
    var availableCalendars: [(id: String, title: String)] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        return store.calendars(for: .event)
            .map { (id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title < $1.title }
    }

    /// Empty means all — see `selectionKey`.
    var selectedIdentifiers: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.selectionKey) ?? []) }
        set { defaults.set(Array(newValue), forKey: Self.selectionKey) }
    }

    func isIncluded(_ identifier: String) -> Bool {
        let selection = selectedIdentifiers
        return selection.isEmpty || selection.contains(identifier)
    }

    /// Toggling the last remaining calendar off would mean "sync nothing", which
    /// is what disconnecting is for — so it falls back to including everything
    /// rather than silently producing an empty sync the reader cannot explain.
    func setIncluded(_ included: Bool, for identifier: String) {
        var selection = selectedIdentifiers
        if selection.isEmpty {
            selection = Set(availableCalendars.map(\.id))
        }
        if included { selection.insert(identifier) } else { selection.remove(identifier) }
        selectedIdentifiers = selection.isEmpty ? [] : selection
    }

    // MARK: - Sync

    /// Reads events and hands them back as `CalendarEvent`s.
    ///
    /// Returns no `SyncedData` content: a calendar produces no samples and no
    /// raw metric rows, so claiming either would put meetings into the vitals
    /// layer. The events reach the app through `fetchEvents()` instead, which is
    /// the honest shape even though it means this one integration is not purely
    /// described by the protocol.
    func sync() async throws -> SyncedData {
        // The events are pulled and stored by `AppModel.syncCalendar()`, which
        // also classifies them — this only stamps the sync so the Settings row
        // can say when it last ran. Fetching here as well would read the store
        // twice per sync for nothing.
        defaults.set(Date(), forKey: Self.lastSyncKey)
        return SyncedData()
    }

    /// The video-conference hosts worth recognising. A list rather than "is a
    /// URL", because a link to an agenda is not a way of attending.
    private static let videoHosts = [
        "zoom.us", "teams.microsoft", "teams.live", "meet.google", "webex",
        "whereby.com", "gotomeeting", "bluejeans", "chime.aws", "facetime",
    ]

    private static func mentionsVideoCall(_ text: String?) -> Bool {
        guard let text = text?.lowercased(), !text.isEmpty else { return false }
        return videoHosts.contains { text.contains($0) }
    }

    /// Whether the event's organiser is the reader — the fact, derived here and
    /// kept; the address, read here and dropped. The same discipline as the
    /// video link below, applied to B7 H2's question ("did I organise this?").
    ///
    /// Three states, in evidence order:
    /// - no organiser at all → nil (the shape of a self-created event — that is
    ///   *unknown*, and the classifier treats it as such);
    /// - EventKit's own `isCurrentUser` → true (the calendar account holder);
    /// - otherwise the organiser's `mailto:` URL against the reader's stated
    ///   emails (H1) — which is exactly what those emails were entered to
    ///   answer, and catches the account the phone does not know is theirs.
    private static func organizerIsReader(_ event: EKEvent,
                                          identity: ReaderIdentity?) -> Bool? {
        guard let organizer = event.organizer else { return nil }
        if organizer.isCurrentUser { return true }
        return identity?.matches(organizer: organizer.url.absoluteString) == true
    }

    /// The events themselves, for whatever stores them.
    ///
    /// `identity` (B7 H1) is consulted only to derive the organiser boolean —
    /// nothing of it is stored on the event.
    func fetchEvents(now: Date = Date(),
                     identity: ReaderIdentity? = nil) throws -> [CalendarEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendar = Calendar.current
        guard let from = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now),
              let to = calendar.date(byAdding: .day, value: Self.lookaheadDays, to: now)
        else { return [] }

        let included = store.calendars(for: .event).filter { isIncluded($0.calendarIdentifier) }
        guard !included.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: included)
        return store.events(matching: predicate).map { event in
            let isMultiDay = event.isAllDay
                && (calendar.dateComponents([.day], from: event.startDate,
                                            to: event.endDate).day ?? 0) >= 1
            return CalendarEvent(
                // `eventIdentifier` is stable for a non-recurring event and
                // shared across a recurring series — so the occurrence's start
                // is folded in, or every weekly stand-up would collapse to one
                // row and a year of them would look like a single meeting.
                id: "\(event.eventIdentifier ?? UUID().uuidString)|\(event.startDate.timeIntervalSince1970)",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                timeZoneIdentifier: event.timeZone?.identifier,
                calendarName: event.calendar.title,
                kind: isMultiDay ? .multiDay : (event.isAllDay ? .allDay : .timed),
                title: event.title ?? "",
                location: event.location,
                // ⚠️ **The link is detected and not kept.** "Did it include a
                // remote meeting link" is the question the reader asked; the URL
                // itself answers nothing further and is one more identifying
                // string to hold. Notes are read here and never stored, for the
                // same reason — this is the only place they are touched.
                hasVideoLink: Self.mentionsVideoCall(event.location)
                    || Self.mentionsVideoCall(event.url?.absoluteString)
                    || Self.mentionsVideoCall(event.notes),
                organizerIsReader: Self.organizerIsReader(event, identity: identity),
                // ⚠️ **The count, and the list dies with this closure.** Same
                // discipline as the two lines above, applied to B8 R3's
                // artifact: "six people were in the room" is a real signal about
                // a meeting; six names are six other people's data, in an app
                // that holds one person's. `nil` where the event carries no
                // attendee records at all — unknown, not zero.
                attendeeCount: event.attendees?.count)
        }
    }
}
