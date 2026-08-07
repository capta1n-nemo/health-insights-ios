import XCTest
@testable import InsightKit

/// Backlog B18-2. Two things are worth failing a build over here: the **keying**
/// — an evening's phone use against the night that *followed* it, never the one
/// before — and the **refusal**, because with twenty-six days of screen time on
/// the reader's export a contrast that fires too early is the likeliest way this
/// section says something untrue.
final class ScreenTimeSleepLinkTests: XCTestCase {

    private let calendar = Calendar.current

    private var day0: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day0) ?? day0
    }

    private func sample(_ type: MetricType, _ value: Double, on date: Date) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value, start: date, end: date, source: .manual)
    }

    // MARK: - The keying

    func testAnEveningsScreenTimeIsPairedWithTheNightThatFollowedIt() throws {
        let samples = [
            sample(.screenTimeMinutes, 300, on: day(0)),
            sample(.sleepDurationHours, 5, on: day(0)),   // the night BEFORE it
            sample(.sleepDurationHours, 8, on: day(1))    // the night after
        ]
        let link = ScreenTimeSleepLink.build(samples: samples, calendar: calendar)
        let pair = try XCTUnwrap(link.pairs.first)
        XCTAssertEqual(pair.day, day(0))
        XCTAssertEqual(pair.night, day(1))
        XCTAssertEqual(pair.sleepHours, 8,
                       "pairing a day with its own key would hold phone use against "
                           + "sleep that happened before it")
    }

    func testADayWithNoNightBesideItIsNotAPair() {
        let link = ScreenTimeSleepLink.build(
            samples: [sample(.screenTimeMinutes, 300, on: day(0))], calendar: calendar)
        XCTAssertTrue(link.pairs.isEmpty)
        XCTAssertEqual(link.coverage?.have, 0)
    }

    // MARK: - The refusal

    func testNoContrastBelowTheFloorAndItSaysHowManyMore() throws {
        var samples: [HealthMetricSample] = []
        for index in 0..<6 {
            samples.append(sample(.screenTimeMinutes, Double(100 + index * 60), on: day(index)))
            samples.append(sample(.sleepDurationHours, 8 - Double(index) * 0.4,
                                  on: day(index + 1)))
        }
        let link = ScreenTimeSleepLink.build(samples: samples, calendar: calendar)
        XCTAssertEqual(link.pairs.count, 6)
        XCTAssertTrue(link.contrasts.isEmpty, "six pairs is arithmetic, not evidence")
        let gate = try XCTUnwrap(link.coverage)
        XCTAssertEqual(gate.remaining, ScreenTimeSleepLink.minimumPairs - 6)
        XCTAssertNotNil(gate.sentence)
    }

    func testAContrastArrivesOnceThereAreEnoughPairs() throws {
        var samples: [HealthMetricSample] = []
        for index in 0..<20 {
            // Alternating heavy and light evenings, with the heavy ones followed
            // by shorter nights.
            let heavy = index.isMultiple(of: 2)
            samples.append(sample(.screenTimeMinutes, heavy ? 600 : 120, on: day(index)))
            samples.append(sample(.sleepDurationHours, heavy ? 6 : 8, on: day(index + 1)))
        }
        let link = ScreenTimeSleepLink.build(samples: samples, calendar: calendar)
        XCTAssertNil(link.coverage, "a met gate says nothing")
        let contrast = try XCTUnwrap(link.contrasts.first { $0.outcome == .sleepHours })
        XCTAssertEqual(contrast.difference, -2, accuracy: 0.01)
        XCTAssertTrue(contrast.sentence.contains("worse"))
        XCTAssertTrue(contrast.sentence.contains("not\nwhat caused it")
                      || contrast.sentence.contains("not what caused it"),
                      "an association is never reported as a cause")
    }

    func testADifferenceInsideTheFloorIsReportedAsNoDifference() throws {
        var samples: [HealthMetricSample] = []
        for index in 0..<20 {
            let heavy = index.isMultiple(of: 2)
            samples.append(sample(.screenTimeMinutes, heavy ? 600 : 120, on: day(index)))
            samples.append(sample(.sleepDurationHours, heavy ? 7.95 : 8, on: day(index + 1)))
        }
        let link = ScreenTimeSleepLink.build(samples: samples, calendar: calendar)
        let contrast = try XCTUnwrap(link.contrasts.first { $0.outcome == .sleepHours })
        XCTAssertTrue(contrast.sentence.contains("about the same"))
    }

    /// An outcome the reader has almost none of must not ride in on the back of
    /// one they have plenty of.
    func testAnOutcomeWithTooFewNightsIsSkippedRatherThanContrasted() {
        var samples: [HealthMetricSample] = []
        for index in 0..<20 {
            let heavy = index.isMultiple(of: 2)
            samples.append(sample(.screenTimeMinutes, heavy ? 600 : 120, on: day(index)))
            samples.append(sample(.sleepDurationHours, heavy ? 6 : 8, on: day(index + 1)))
        }
        samples.append(sample(.sleepLatencyMinutes, 30, on: day(1)))
        let link = ScreenTimeSleepLink.build(samples: samples, calendar: calendar)
        XCTAssertFalse(link.contrasts.contains { $0.outcome == .latencyMinutes })
    }
}
