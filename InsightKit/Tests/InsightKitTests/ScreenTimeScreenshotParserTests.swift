import XCTest
@testable import InsightKit

/// Reading a Screen Time screenshot. The load-bearing claim is not "it finds a
/// number" — it is that it knows **which** number it found, because "Daily
/// Average" sits inches from the day's total on the same screen and is usually
/// the bigger, bolder one.
final class ScreenTimeScreenshotParserTests: XCTestCase {

    private let cal = TestClock.utc
    private var now: Date { TestClock.now }

    private func parse(_ text: String) -> ScreenTimeScreenshotParser.Result {
        ScreenTimeScreenshotParser.parse(text, capturedAt: now, calendar: cal)
    }

    // MARK: - Durations

    func testTheDurationShapesScreenTimeActuallyRenders() {
        func d(_ line: String) -> Double? { ScreenTimeScreenshotParser.duration(in: line) }
        XCTAssertEqual(d("4h 32m"), 272)
        XCTAssertEqual(d("4h32m"), 272)
        XCTAssertEqual(d("4 h 32 m"), 272)
        XCTAssertEqual(d("32m"), 32)
        XCTAssertEqual(d("4h"), 240)
        XCTAssertEqual(d("Total Screen Time 1h 5m"), 65)
    }

    /// A bare number on this screen is a pickup count, not a duration. Reading
    /// it as minutes is how "87 pickups" becomes an hour and a half of screen
    /// time.
    func testABareNumberIsNotADuration() {
        XCTAssertNil(ScreenTimeScreenshotParser.duration(in: "87"))
        XCTAssertNil(ScreenTimeScreenshotParser.duration(in: "Pickups"))
    }

    // MARK: - The distinction that matters

    /// **The whole point.** The average is the larger number and appears first;
    /// a "biggest duration wins" parser would record it as the day.
    func testTheDailyAverageIsNeverOfferedAsADaysTotal() throws {
        let result = parse("""
        Screen Time
        Daily Average
        5h 32m
        Today
        3h 12m
        """)
        let day = try XCTUnwrap(result.dayTotal)
        XCTAssertEqual(day.minutes, 192, "today's 3h 12m, not the 5h 32m average")
        XCTAssertTrue(result.readings.contains {
            $0.kind == .dailyAverage && $0.minutes == 332
        }, "the average is still reported, just not as a day")
    }

    /// A screenshot showing only the average yields **no** day total. Offering
    /// one would be inventing the number the reader came for.
    func testAnAverageOnlyScreenshotOffersNoDayTotal() {
        let result = parse("""
        Screen Time
        Daily Average
        5h 32m
        """)
        XCTAssertNil(result.dayTotal)
        XCTAssertEqual(result.otherReadings.first?.kind, .dailyAverage)
    }

    func testAWeeksTotalIsNotADaysTotal() {
        let result = parse("""
        This Week
        Total 38h 44m
        """)
        XCTAssertNil(result.dayTotal)
        XCTAssertEqual(result.readings.first?.kind, .weeklyTotal)
    }

    /// The common day view, where the heading and the figure share a line.
    func testTheDayViewIsRead() throws {
        let result = parse("""
        Tuesday, 5 August
        Total Screen Time
        4h 32m
        Pickups
        87
        """)
        let day = try XCTUnwrap(result.dayTotal)
        XCTAssertEqual(day.minutes, 272)
        XCTAssertEqual(result.pickups, 87)
    }

    func testPickupsAndNotificationsOnTheSameLineAsTheirLabel() {
        let result = parse("""
        Today
        2h 5m
        Pickups 143
        Notifications 512
        """)
        XCTAssertEqual(result.pickups, 143)
        XCTAssertEqual(result.notifications, 512)
    }

    /// A heading following the label must not be read as its count.
    func testALabelFollowedByWordsYieldsNoCount() {
        let result = parse("""
        Pickups
        First Used After Pickup
        Today
        1h
        """)
        XCTAssertNil(result.pickups)
    }

    // MARK: - Dates

    func testTodayAndYesterdayResolve() throws {
        let today = try XCTUnwrap(parse("Today\n1h").date)
        XCTAssertEqual(today, cal.startOfDay(for: now))

        let yesterday = try XCTUnwrap(parse("Yesterday\n1h").date)
        XCTAssertEqual(yesterday,
                       cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)))
    }

    /// A weekday names the most recent one, never a future date — a Screen Time
    /// screenshot is always about the past.
    func testAWeekdayResolvesBackwards() throws {
        let date = try XCTUnwrap(parse("Monday\nTotal Screen Time\n2h").date)
        XCTAssertLessThanOrEqual(date, cal.startOfDay(for: now))
        XCTAssertEqual(cal.component(.weekday, from: date), 2, "Monday")
    }

    func testNoDayNamedMeansNoDate() {
        XCTAssertNil(parse("Total Screen Time\n3h 20m").date)
    }

    // MARK: - Rubbish in

    func testAnUnrelatedScreenshotYieldsNothing() {
        let result = parse("""
        Settings
        General
        About
        """)
        XCTAssertTrue(result.isEmpty)
        XCTAssertNil(result.dayTotal)
    }

    /// OCR of a busy screen produces stray numbers. A duration with no words
    /// near it is kept but marked unlabelled, never promoted to a day's total.
    func testAnUnlabelledDurationIsNotPromoted() {
        let result = parse("""
        Instagram
        1h 12m
        """)
        XCTAssertNil(result.dayTotal)
        XCTAssertEqual(result.readings.first?.kind, .unlabelled)
    }
}
