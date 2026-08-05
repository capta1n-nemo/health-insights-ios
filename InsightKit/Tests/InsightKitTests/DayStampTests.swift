import XCTest
@testable import InsightKit

/// **A date-only field names a calendar day, and a calendar day is local.**
///
/// The app resolved that two ways at once: the two ingestion formatters were
/// pinned to UTC (the only two `TimeZone(identifier: "UTC")` in the whole
/// codebase) while `SleepOnset.night`, `ShortcutIngest` and every manual write
/// used `calendar.startOfDay`. In the reader's own export that is 1,720 Oura
/// samples at exactly `T00:00:00Z` against 135 Apple sleep samples at exactly
/// `T16:00:00Z` — which is the same local midnight, at UTC+8.
///
/// **They agree only by accident, and the accident is the sign of the offset.**
/// `startOfDay(midnightUTC(D))` is `D` at a non-negative offset and `D − 1` at a
/// negative one. So this is not a live misregistration for this reader today and
/// must not be reported as a sensitivity fix — it is the removal of a
/// coincidence that breaks on the first flight west.
final class DayStampTests: XCTestCase {

    private func calendar(_ identifier: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: identifier)!
        return c
    }

    /// The rule, at four offsets including both signs. The old UTC formatter
    /// passes this at UTC and nowhere else, which is why one-zone testing hid it.
    func testADayLandsOnItsOwnZonesMidnight() throws {
        for zone in ["UTC", "Asia/Tokyo", "Asia/Manila", "America/New_York"] {
            let c = calendar(zone)
            let stamped = try XCTUnwrap(DayStamp.local("2026-01-10", calendar: c), zone)
            XCTAssertEqual(c.startOfDay(for: stamped), stamped, "not midnight in \(zone)")
            XCTAssertEqual(c.component(.day, from: stamped), 10, "wrong day in \(zone)")
        }
    }

    /// The same string is a *different instant* in different zones — the
    /// property the UTC formatter destroyed by returning one instant for all.
    func testTheSameDayIsADifferentInstantInEachZone() throws {
        let tokyo = try XCTUnwrap(DayStamp.local("2026-01-10", calendar: calendar("Asia/Tokyo")))
        let newYork = try XCTUnwrap(DayStamp.local("2026-01-10", calendar: calendar("America/New_York")))
        XCTAssertNotEqual(tokyo, newYork)
        XCTAssertEqual(newYork.timeIntervalSince(tokyo), 14 * 3600, accuracy: 1,
                       "UTC+9 to UTC−5 is fourteen hours")
    }

    /// A zone whose clocks move at midnight is the reason for the `startOfDay`
    /// wrap: `date(from:)` on a bare y/m/d can land at 23:00 the previous day,
    /// and every downstream day-bucket would then disagree with the field it
    /// came from. Cuba jumps 00:00 → 01:00 on 8 March 2026.
    func testAMidnightDSTTransitionStillLandsOnTheNamedDay() throws {
        let c = calendar("America/Havana")
        let stamped = try XCTUnwrap(DayStamp.local("2026-03-08", calendar: c))
        XCTAssertEqual(c.component(.day, from: stamped), 8,
                       "a midnight DST jump moved the stamp to the previous day")
        XCTAssertEqual(c.startOfDay(for: stamped), stamped)
    }

    /// Rubbish in, nil out — the same guards `ShortcutIngest.parseDate` applies.
    func testMalformedDaysAreRejected() {
        let c = calendar("UTC")
        for bad in ["", "2026", "2026-01", "2026-13-01", "2026-01-32", "not-a-date", "20260110"] {
            XCTAssertNil(DayStamp.local(bad, calendar: c), "accepted \(bad)")
        }
    }

    // MARK: - The rule must stay keyed on the string, never on the date

    /// `PayloadDate` sends only the ten-character branch through `DayStamp`. An
    /// instant carrying a time of day must come back byte-identical, because the
    /// tempting alternative rule — "if it is midnight UTC, shift it" — would
    /// corrupt the 109 HealthKit samples in the reader's export that genuinely
    /// land at `T00:00:00Z` having touched no formatter at all.
    func testAnInstantIsNeverReinterpretedAsADay() throws {
        let manila = calendar("Asia/Manila")
        let iso = "2026-01-10T00:00:00+00:00"
        let parsed = try XCTUnwrap(PayloadDate.parse(iso, calendar: manila))
        XCTAssertEqual(parsed.timeIntervalSince1970,
                       try XCTUnwrap(PayloadDate.parse(iso, calendar: calendar("UTC"))).timeIntervalSince1970,
                       accuracy: 0.001,
                       "an explicit instant was re-read against the calendar — it carries its own offset")
    }

    /// Epoch seconds are an instant too, and Withings sends them.
    func testEpochSecondsAreZoneIndependent() throws {
        let a = try XCTUnwrap(PayloadDate.parse(NSNumber(value: 1_767_000_000), calendar: calendar("Asia/Tokyo")))
        let b = try XCTUnwrap(PayloadDate.parse(NSNumber(value: 1_767_000_000), calendar: calendar("America/New_York")))
        XCTAssertEqual(a, b)
    }

    /// The ten-character branch is the *only* one that consults the calendar.
    func testOnlyABareDayConsultsTheCalendar() throws {
        let tokyo = calendar("Asia/Tokyo"), newYork = calendar("America/New_York")
        // A day: differs by zone.
        XCTAssertNotEqual(PayloadDate.parse("2026-01-10", calendar: tokyo),
                          PayloadDate.parse("2026-01-10", calendar: newYork))
        // An instant with a fractional second: identical in both.
        XCTAssertEqual(PayloadDate.parse("2026-01-10T08:30:00.500+08:00", calendar: tokyo),
                       PayloadDate.parse("2026-01-10T08:30:00.500+08:00", calendar: newYork))
    }
}
