import XCTest
@testable import InsightKit

/// The Shortcuts transport. It is deliberately generic — any `MetricType` can
/// arrive through it, including ones no connector exists for yet — so what has
/// to be pinned is the *contract*: what it accepts, what it refuses, and that it
/// says which is which.
final class ShortcutIngestTests: XCTestCase {

    private let cal = TestClock.utc
    private var now: Date { TestClock.now }

    private func url(_ query: String) -> URL {
        URL(string: "healthinsights://shortcut?\(query)")!
    }

    func testItOnlyHandlesItsOwnHost() {
        XCTAssertTrue(ShortcutIngest.handles(url("screenTimeMinutes=100")))
        XCTAssertFalse(ShortcutIngest.handles(URL(string: "healthinsights://oauth/oura?code=1")!))
        XCTAssertNil(ShortcutIngest.parse(URL(string: "healthinsights://oauth/oura")!,
                                          now: now, calendar: cal))
    }

    /// The shape the setup screen tells the reader to build.
    func testAReadingArrivesWithItsDateAndSource() throws {
        let result = try XCTUnwrap(ShortcutIngest.parse(
            url("date=2026-08-02&screenTimeMinutes=252"), now: now, calendar: cal))
        XCTAssertEqual(result.samples.count, 1)
        let sample = try XCTUnwrap(result.samples.first)
        XCTAssertEqual(sample.type, .screenTimeMinutes)
        XCTAssertEqual(sample.value, 252)
        XCTAssertEqual(sample.source, .shortcuts)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: sample.start).day, 2)
        XCTAssertTrue(result.unknownKeys.isEmpty)
        XCTAssertTrue(result.rejectedKeys.isEmpty)
    }

    /// **The extensibility claim, tested.** The transport knows nothing about
    /// which metrics exist — so a metric added later works through the same
    /// shortcut with no change to this code and none to the automation's shape.
    func testAnyMetricTypeCanArriveThroughIt() throws {
        for metric in [MetricType.stepCount, .bodyMass, .respiratoryRate] {
            let result = try XCTUnwrap(ShortcutIngest.parse(
                url("\(metric.rawValue)=42"), now: now, calendar: cal))
            XCTAssertEqual(result.samples.first?.type, metric)
        }
    }

    func testSeveralReadingsCanArriveInOneRun() throws {
        let result = try XCTUnwrap(ShortcutIngest.parse(
            url("date=2026-08-02&screenTimeMinutes=252&stepCount=8000"),
            now: now, calendar: cal))
        XCTAssertEqual(Set(result.samples.map(\.type)), [.screenTimeMinutes, .stepCount])
    }

    /// A typo must be reported rather than swallowed — the reader would
    /// otherwise believe they are collecting something they are not.
    func testAnUnknownKeyIsNamedNotGuessedAt() throws {
        let result = try XCTUnwrap(ShortcutIngest.parse(
            url("screenTimeMinuts=252"), now: now, calendar: cal))
        XCTAssertTrue(result.samples.isEmpty)
        XCTAssertEqual(result.unknownKeys, ["screenTimeMinuts"])
    }

    /// The commonest failure in a hand-built shortcut is a unit slip. Guarding
    /// on the metric's own plausible range stops milliseconds-for-minutes
    /// poisoning a baseline.
    func testAnImplausibleValueIsRejected() throws {
        let result = try XCTUnwrap(ShortcutIngest.parse(
            url("screenTimeMinutes=86400000"), now: now, calendar: cal))
        XCTAssertTrue(result.samples.isEmpty)
        XCTAssertEqual(result.rejectedKeys, ["screenTimeMinutes"])

        // And the boundary is allowed: a whole day of screen time is possible.
        let atLimit = try XCTUnwrap(ShortcutIngest.parse(
            url("screenTimeMinutes=1440"), now: now, calendar: cal))
        XCTAssertEqual(atLimit.samples.count, 1)
    }

    func testAnUnparseableValueIsRejectedRatherThanZeroed() throws {
        let result = try XCTUnwrap(ShortcutIngest.parse(
            url("screenTimeMinutes=lots"), now: now, calendar: cal))
        XCTAssertTrue(result.samples.isEmpty)
        XCTAssertEqual(result.rejectedKeys, ["screenTimeMinutes"])
    }

    /// Zero screen time is a real day; zero heart rate is a missing reading.
    /// The distinction is the metric's own, not this parser's.
    func testZeroIsKeptOrDroppedPerTheMetricsOwnRule() throws {
        let screen = try XCTUnwrap(ShortcutIngest.parse(
            url("screenTimeMinutes=0"), now: now, calendar: cal))
        XCTAssertEqual(screen.samples.count, 1, "a day off the phone is a real day")

        let heart = try XCTUnwrap(ShortcutIngest.parse(
            url("restingHeartRate=0"), now: now, calendar: cal))
        XCTAssertTrue(heart.samples.isEmpty, "a resting heart rate of zero is missing data")
    }

    func testAMissingDateMeansToday() throws {
        let result = try XCTUnwrap(ShortcutIngest.parse(
            url("screenTimeMinutes=100"), now: now, calendar: cal))
        let day = try XCTUnwrap(result.samples.first?.start)
        XCTAssertEqual(cal.startOfDay(for: now), day)
    }

    /// Shortcuts' own "Format Date" produces both of these without the reader
    /// having to think about it.
    func testBothDateShapesParse() {
        XCTAssertNotNil(ShortcutIngest.parseDate("2026-08-02", calendar: cal))
        XCTAssertNotNil(ShortcutIngest.parseDate("2026-08-02T21:30:00Z", calendar: cal))
        XCTAssertNil(ShortcutIngest.parseDate("02/08/2026", calendar: cal))
        XCTAssertNil(ShortcutIngest.parseDate("", calendar: cal))
    }
}
