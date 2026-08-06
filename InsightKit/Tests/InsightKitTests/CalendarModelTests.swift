import XCTest
@testable import InsightKit

/// The calendar, as the two requested cards will read it.
///
/// It is tested in InsightKit rather than in the app target for the reason the
/// whole package exists: `EventKit` is not available on Linux, and a card that
/// reads the calendar has to be testable without a device. The app fetches;
/// this is what the fetching produces.
final class CalendarModelTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    private func event(dayOffset: Int, startHour: Int, hours: Double,
                       zone: String? = "Europe/London",
                       kind: CalendarEvent.Kind = .timed,
                       calendarName: String = "Work") -> CalendarEvent {
        let day = utc.startOfDay(for: now.addingTimeInterval(Double(dayOffset) * 86_400))
        let start = day.addingTimeInterval(Double(startHour) * 3600)
        return CalendarEvent(id: "\(dayOffset)-\(startHour)", start: start,
                             end: start.addingTimeInterval(hours * 3600),
                             isAllDay: kind != .timed, timeZoneIdentifier: zone,
                             calendarName: calendarName, kind: kind)
    }

    func testCommittedHoursAddsUpTheTimedEventsOnADay() {
        let events = [event(dayOffset: 0, startHour: 9, hours: 1),
                      event(dayOffset: 0, startHour: 14, hours: 2.5),
                      event(dayOffset: -1, startHour: 10, hours: 8)]
        XCTAssertEqual(CalendarModel.committedHours(events, on: now, calendar: utc),
                       3.5, accuracy: 0.001)
    }

    /// ⚠️ **An all-day marker is not a day of work.** Counting one as 24 hours
    /// would make every calendar with birthdays in it look uniformly full, which
    /// is the fastest way to make a "how busy were you" card useless.
    func testAnAllDayMarkerIsNotCountedAsAFullDay() {
        let events = [event(dayOffset: 0, startHour: 0, hours: 24, kind: .allDay)]
        XCTAssertEqual(CalendarModel.committedHours(events, on: now, calendar: utc), 0)
    }

    /// A meeting spanning midnight is clipped to the day, so it is neither
    /// counted twice nor attributed wholly to one side of it.
    func testAnEventSpanningMidnightIsClippedRatherThanDoubleCounted() {
        let events = [event(dayOffset: -1, startHour: 22, hours: 4)]
        let yesterday = now.addingTimeInterval(-86_400)
        XCTAssertEqual(CalendarModel.committedHours(events, on: yesterday, calendar: utc),
                       2, accuracy: 0.001)
        XCTAssertEqual(CalendarModel.committedHours(events, on: now, calendar: utc),
                       2, accuracy: 0.001)
    }

    /// **The travel signal**, and the reason the time zone is stored at all: the
    /// app captures no HealthKit metadata, so no sample knows where it was
    /// recorded. A calendar event does.
    func testATimeZoneChangeIsReportedWithTheDayItHappened() throws {
        let events = [event(dayOffset: -10, startHour: 9, hours: 1, zone: "Europe/London"),
                      event(dayOffset: -5, startHour: 9, hours: 1, zone: "Europe/London"),
                      event(dayOffset: -3, startHour: 9, hours: 1, zone: "Asia/Singapore"),
                      event(dayOffset: -1, startHour: 9, hours: 1, zone: "Asia/Singapore")]
        let changes = CalendarModel.timeZoneChanges(events, calendar: utc)
        XCTAssertEqual(changes.count, 1, "one move, reported once — not once per event")
        XCTAssertEqual(changes.first?.zone, "Asia/Singapore")
    }

    /// The first zone seen is not a change — there was nothing to change from.
    func testTheFirstZoneSeenIsNotReportedAsAMove() {
        let events = [event(dayOffset: -2, startHour: 9, hours: 1, zone: "Europe/London")]
        XCTAssertTrue(CalendarModel.timeZoneChanges(events, calendar: utc).isEmpty)
    }

    /// Events with no zone at all must not fabricate a move.
    func testEventsWithoutATimeZoneAreIgnoredRatherThanGuessedAt() {
        let events = [event(dayOffset: -4, startHour: 9, hours: 1, zone: nil),
                      event(dayOffset: -2, startHour: 9, hours: 1, zone: nil)]
        XCTAssertTrue(CalendarModel.timeZoneChanges(events, calendar: utc).isEmpty)
    }

    func testTheBusiestDayIsTheOneWithTheMostCommittedHours() throws {
        let events = [event(dayOffset: -3, startHour: 9, hours: 2),
                      event(dayOffset: -1, startHour: 9, hours: 6),
                      event(dayOffset: -1, startHour: 16, hours: 1)]
        let busiest = try XCTUnwrap(CalendarModel.busiestDay(events, now: now, calendar: utc))
        XCTAssertEqual(busiest.hours, 7, accuracy: 0.001)
    }

    /// ⚠️ **The privacy shape is part of the type, not a convention** — and this
    /// test now guards a *different* rule from the one it was written for.
    ///
    /// It originally asserted the type carried no title and no location, so that
    /// widening it would be a decision somebody took rather than a struct
    /// drifting. **The decision was taken, by the reader, hours later**: they
    /// asked for the events to be read and classified. So the content is here.
    ///
    /// What survives is the part that always mattered: **notes and attendees are
    /// still not stored.** None of the six judgements the reader asked for needs
    /// the body of an event or the list of people in it, and those two fields
    /// are where a calendar stops being a schedule and becomes a dossier. A
    /// video link is kept as a *boolean* for the same reason — "was it remote"
    /// is the question; the URL is not.
    ///
    /// `organizerIsReader` joined with B7 H2, and it is the boolean pattern
    /// again, taken deliberately: the reader asked the app to be *"email aware,
    /// and user aware"* so it can tell whose OOO block an event is, and the
    /// answer to "did I organise this" is yes/no/unknown — the organiser's
    /// *address* answers nothing further and stays banned below.
    func testTheEventStoresNoNotesAndNoAttendees() {
        let mirror = Mirror(reflecting: event(dayOffset: 0, startHour: 9, hours: 1))
        let fields = Set(mirror.children.compactMap(\.label))
        for banned in ["notes", "attendees", "organizer", "url", "body", "description"] {
            XCTAssertFalse(fields.contains(banned),
                           "CalendarEvent grew a \(banned) field — that is a privacy decision, not a refactor")
        }
        XCTAssertEqual(fields, ["id", "start", "end", "isAllDay",
                                "timeZoneIdentifier", "calendarName", "kind",
                                "title", "location", "hasVideoLink",
                                "organizerIsReader"])
    }
}
