import XCTest
@testable import InsightKit

/// The URL the app hands out must be the URL the app reads back.
///
/// Until the builder existed there were two hand-written copies of this format —
/// one in `ShortcutsIntegrationView`'s template literal, one implied by
/// `ShortcutIngest.parse` — and a third was about to be written for the App
/// Intent. Two string literals agreeing is a hope; a round trip is a test.
final class ShortcutURLBuilderTests: XCTestCase {

    private let calendar = TestClock.utc

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))!
    }

    /// **The contract.** Whatever the builder emits, the parser recovers.
    func testARoundTripRecoversEveryReading() throws {
        let date = day(2026, 8, 2)
        let url = try XCTUnwrap(ShortcutIngest.url(
            for: [.screenTimeMinutes: 252, .sleepLatencyMinutes: 18],
            on: date, calendar: calendar))

        let result = try XCTUnwrap(ShortcutIngest.parse(url, calendar: calendar))
        XCTAssertEqual(result.unknownKeys, [], "the builder emitted a key the parser rejects")
        XCTAssertEqual(result.rejectedKeys, [])
        XCTAssertEqual(Set(result.samples.map(\.type)),
                       [.screenTimeMinutes, .sleepLatencyMinutes])
        for sample in result.samples {
            XCTAssertEqual(sample.start, date)
            XCTAssertEqual(sample.source, .shortcuts)
        }
        XCTAssertEqual(result.samples.first { $0.type == .screenTimeMinutes }?.value, 252)
        XCTAssertEqual(result.samples.first { $0.type == .sleepLatencyMinutes }?.value, 18)
    }

    /// A fractional reading survives the trip too — the number formatter must not
    /// quietly round, and must never emit an exponent `Double(_:)` would choke on.
    func testAFractionalValueSurvives() throws {
        let url = try XCTUnwrap(ShortcutIngest.url(
            for: [.bodyMass: 110.45], on: day(2026, 8, 2), calendar: calendar))
        let result = try XCTUnwrap(ShortcutIngest.parse(url, calendar: calendar))
        XCTAssertEqual(result.rejectedKeys, [])
        XCTAssertEqual(result.samples.first?.value ?? 0, 110.45, accuracy: 1e-9)
    }

    /// The same readings always produce the same URL, so a template on screen
    /// does not reshuffle itself between two looks at it.
    func testTheOutputIsStable() throws {
        let values: [MetricType: Double] = [.screenTimeMinutes: 1, .bodyMass: 2,
                                            .sleepLatencyMinutes: 3]
        let first = ShortcutIngest.url(for: values, on: day(2026, 8, 2), calendar: calendar)
        for _ in 0..<20 {
            XCTAssertEqual(ShortcutIngest.url(for: values, on: day(2026, 8, 2),
                                              calendar: calendar), first)
        }
    }

    /// Dates are zero-padded, because `2026-8-2` is not what the parser's
    /// ten-character prefix expects and would silently take the wrong slice.
    func testDatesAreZeroPadded() {
        XCTAssertEqual(ShortcutIngest.dateString(day(2026, 8, 2), calendar: calendar),
                       "2026-08-02")
        XCTAssertEqual(ShortcutIngest.dateString(day(2026, 12, 25), calendar: calendar),
                       "2026-12-25")
        XCTAssertEqual(ShortcutIngest.dateString(day(999, 1, 1), calendar: calendar),
                       "0999-01-01")
    }

    /// And a padded date parses back to the day it names.
    func testEveryDayOfAYearRoundTrips() throws {
        var date = day(2026, 1, 1)
        for _ in 0..<365 {
            let text = ShortcutIngest.dateString(date, calendar: calendar)
            XCTAssertEqual(ShortcutIngest.parseDate(text, calendar: calendar), date,
                           "\(text) did not read back as itself")
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
    }

    /// The on-screen template is the same format, so what the reader copies is
    /// what the app accepts — with `VALUE` substituted.
    func testTheTemplateParsesOnceValuesAreSubstituted() throws {
        let template = ShortcutIngest.urlTemplate(for: [.screenTimeMinutes])
        XCTAssertTrue(template.hasPrefix("healthinsights://shortcut?"))
        XCTAssertTrue(template.contains("\(MetricType.screenTimeMinutes.rawValue)=VALUE"))

        let filled = template
            .replacingOccurrences(of: "YYYY-MM-DD", with: "2026-08-02")
            .replacingOccurrences(of: "VALUE", with: "252")
        let result = try XCTUnwrap(ShortcutIngest.parse(
            try XCTUnwrap(URL(string: filled)), calendar: calendar))
        XCTAssertEqual(result.unknownKeys, [], "the template names a key the parser rejects")
        XCTAssertEqual(result.rejectedKeys, [])
        XCTAssertEqual(result.samples.first?.value, 252)
        XCTAssertEqual(result.samples.first?.start, day(2026, 8, 2))
    }

    /// **Every metric, not just the ones with a recipe.** The transport's claim
    /// is that anything that is a `MetricType` can arrive this way, and a key
    /// the parser refuses would break that silently for one signal.
    func testEveryMetricTypeSurvivesTheRoundTrip() throws {
        for metric in MetricType.allCases {
            // A value each metric's own plausibility guard accepts.
            let value = metric.plausibleRange.map { range in
                (range.lowerBound + range.upperBound) / 2
            } ?? (metric.requiresPositiveValue ? 1 : 0)
            let url = try XCTUnwrap(ShortcutIngest.url(for: [metric: value],
                                                       on: day(2026, 8, 2),
                                                       calendar: calendar),
                                    "\(metric.rawValue) produced no URL")
            let result = try XCTUnwrap(ShortcutIngest.parse(url, calendar: calendar))
            XCTAssertEqual(result.unknownKeys, [], "\(metric.rawValue) came back unknown")
            XCTAssertEqual(result.samples.first?.type, metric,
                           "\(metric.rawValue) did not round-trip")
        }
    }
}
