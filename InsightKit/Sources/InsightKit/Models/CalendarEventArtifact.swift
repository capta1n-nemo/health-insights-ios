import Foundation

/// **The event as it stood when the app judged it** — the third layer of the
/// correction record, and the one that was missing.
///
/// Backlog B8 R3, the reader's words: *"make sure for model improvement, we
/// remember the 'AI Estimated' and 'Corrected' data points, in addition to the
/// whole email/artifact, so when we feed this back for improvement, it has all
/// the context to improve the model."*
///
/// ## Why a snapshot rather than a reference to the event
///
/// `CalendarEventJudgement` already kept the guess and the reader's correction
/// apart, which is the hard half (backlog C4). Without this third layer a
/// correction is a **tally** — "the app was wrong 14 times" — and nothing can
/// be learnt from it, because the thing it was wrong *about* is gone. With it,
/// the record is a labelled example: here is what the model read, here is what
/// it concluded, here is what was actually true.
///
/// ⚠️ **It is captured at classification time, never at correction time.** The
/// model judged one particular version of an event. A meeting renamed, moved or
/// re-invited afterwards is a *different* artifact, and snapshotting it when the
/// reader taps "corrected" would silently rewrite what the model was given —
/// producing a training pair the model never actually saw and an accuracy figure
/// computed against words that did not exist at the time. So the write path is
/// `DataStore.recordClassification`, which stores the guess and this snapshot
/// together and cannot see a correction at all; and the pair moves together on a
/// re-classification (`CalendarEventJudgement.reclassified(as:artifact:)`), so
/// the stored guess and the stored artifact are always each other's.
///
/// ## What it holds, and what it still refuses to hold
///
/// `title` and `location` are the most identifying strings this app keeps, and
/// they are here for the same reason `CalendarEvent` holds them: the reader
/// asked for the events to be read and classified, and a correction with the
/// words removed cannot teach anything about words. What is *still* refused is
/// unchanged from `CalendarIntegration`:
///
/// - **No attendee list, no notes, no organiser address, no meeting URL.**
///   `attendeeCount` is a number, not a guest list; `hasVideoLink` and
///   `organizerIsReader` are booleans that answer the reader's actual questions
///   without keeping the strings behind them.
/// - **Nothing here leaves the phone except under `SharingTier.full`**, and the
///   free-text fields are exactly the ones `SharingTier.metadataOnly` drops.
///   That is enforced in one place (`SharingTier.shape(kind:fields:)`) rather
///   than remembered per call site.
public struct CalendarEventArtifact: Sendable, Equatable, Codable, Hashable {

    /// The event's title, as it read when it was classified.
    public let title: String
    /// Where it said to be, when it said anywhere.
    public let location: String?
    /// **How many people, never who.** The count is a genuine signal — a
    /// one-to-one and a twelve-person workshop are different things, and the
    /// reader's "was it a marathon workshop" is partly this — while the guest
    /// list is where a calendar stops being a schedule and becomes a dossier.
    /// Optional because an event may carry no attendees at all, which is not
    /// the same claim as "nobody came".
    public let attendeeCount: Int?
    /// Duration in hours, from the event's own start and end.
    public let durationHours: Double
    /// **When it was due to begin**, as the snapshot read it.
    ///
    /// Optional because rows written before this field existed have none, and a
    /// missing start is *unknown* rather than a claim — `differs(from:)` skips
    /// the comparison rather than reporting a change it cannot see. Same posture
    /// as `attendeeCount` and `organizerIsReader`.
    ///
    /// ⚠️ **Today a moved event usually arrives as a different event.**
    /// `CalendarIntegration.fetchEvents` folds the occurrence's start into the
    /// identifier (`"\(eventIdentifier)|\(startDate.timeIntervalSince1970)"`),
    /// so dragging a meeting mints a new `CalendarEvent.id` and the old
    /// judgement is left behind rather than found to have drifted. This field is
    /// therefore belt-and-braces — and it stops being belt-and-braces the moment
    /// that id scheme changes, which is exactly the kind of change that would
    /// otherwise make drift detection silently blind to the most obvious edit a
    /// reader can make.
    public let start: Date?
    public let isAllDay: Bool
    /// The *calendar's* name — "Work", "Family" — which remains the single
    /// strongest signal for work-versus-personal and is therefore the field a
    /// correction on that axis is most often a correction *about*.
    public let calendarName: String
    public let hasVideoLink: Bool
    /// The organiser fact, never the address — see `CalendarEvent`.
    public let organizerIsReader: Bool?
    /// When this snapshot was taken. **Classification time**, which is what
    /// makes the paragraph above checkable rather than asserted.
    public let capturedAt: Date

    /// `start` is **defaulted**, so the call sites written before the field
    /// existed keep compiling untouched — `SharingExample.calendarCorrection`
    /// and `SharingTierTests`, both of which build a fictional artifact by hand
    /// and have no start to give.
    public init(title: String, location: String?, attendeeCount: Int?,
                durationHours: Double, start: Date? = nil,
                isAllDay: Bool, calendarName: String,
                hasVideoLink: Bool, organizerIsReader: Bool?,
                capturedAt: Date) {
        self.title = title
        self.location = location
        self.attendeeCount = attendeeCount
        self.durationHours = durationHours
        self.start = start
        self.isAllDay = isAllDay
        self.calendarName = calendarName
        self.hasVideoLink = hasVideoLink
        self.organizerIsReader = organizerIsReader
        self.capturedAt = capturedAt
    }

    /// Snapshot an event. The only way this type is built in the app, so "the
    /// artifact is a copy of the event, not a live read of it" is a property of
    /// the code rather than a convention.
    public init(event: CalendarEvent, capturedAt: Date = Date()) {
        self.init(title: event.title,
                  location: event.location,
                  attendeeCount: event.attendeeCount,
                  durationHours: event.durationHours,
                  start: event.start,
                  isAllDay: event.isAllDay,
                  calendarName: event.calendarName,
                  hasVideoLink: event.hasVideoLink,
                  organizerIsReader: event.organizerIsReader,
                  capturedAt: capturedAt)
    }

    /// Whether the event has drifted from the snapshot — the words, the place,
    /// the shape, the size or the slot changed after it was judged.
    ///
    /// **This is what re-judgement is triggered from** (backlog B8 R3 + C4). It
    /// is a pure struct comparison — no rules, no on-device model — which is
    /// what makes it cheap enough to run against every synced event, and it is
    /// deliberately the *only* thing that runs at sync time: what it finds is
    /// queued, and the classifier runs on a boundary. See
    /// `AppModel.flushCalendarReclassification()`.
    public func differs(from event: CalendarEvent) -> Bool {
        title != event.title
            || location != event.location
            || attendeeCount != event.attendeeCount
            || isAllDay != event.isAllDay
            || calendarName != event.calendarName
            || hasVideoLink != event.hasVideoLink
            || abs(durationHours - event.durationHours) > 0.001
            // A snapshot with no start recorded cannot say the event moved, so
            // it says nothing rather than guessing. One second of slack: these
            // round-trip through JSON and a Date is not a decimal.
            || (start.map { abs($0.timeIntervalSince(event.start)) > 1 } ?? false)
    }
}
