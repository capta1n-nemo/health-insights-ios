import XCTest
@testable import InsightKit

/// The night chart's arithmetic, shaped like the night that motivated it:
/// 2026-07-29, where Oura recorded a 4.3 h block and a 4.2 h morning re-sleep
/// while Apple Health filed one 8.5 h window — and nothing on any screen could
/// show that both were true.
final class NightSleepDetailTests: XCTestCase {

    private let calendar = Calendar.current

    /// A fixed local midnight, so hour arithmetic is stable wherever CI runs.
    private var midnight: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
    }
    private func at(_ day: Int, _ hour: Double) -> Date {
        midnight.addingTimeInterval((Double(day) * 24 + hour) * 3600)
    }

    private func raw(_ identifier: String, _ value: RawValue, start: Date) -> RawMetricSample {
        RawMetricSample(id: UUID(), identifier: identifier, displayName: identifier,
                        value: value, unit: "", start: start, source: .oura)
    }

    // MARK: - Phase strings

    func testPhaseRunsBecomeBands() throws {
        let start = at(0, 2)
        let bands = NightSleepDetail.bands(from: "44112233", start: start)
        XCTAssertEqual(bands.map(\.stage), [.awake, .deep, .light, .rem])
        XCTAssertEqual(bands.map(\.hours), [10.0 / 60, 10.0 / 60, 10.0 / 60, 10.0 / 60]
            .map { $0 }, "two five-minute steps per run")
        XCTAssertEqual(bands.first?.start, start)
        XCTAssertEqual(try XCTUnwrap(bands.last).end,
                       start.addingTimeInterval(8 * 300))
    }

    func testAnUnknownCharacterLeavesAGapRatherThanGuessing() {
        let bands = NightSleepDetail.bands(from: "1x1", start: at(0, 2))
        XCTAssertEqual(bands.count, 2)
        XCTAssertTrue(bands.allSatisfy { $0.stage == .deep })
        XCTAssertGreaterThan(bands[1].start, bands[0].end, "the unknown step is a hole")
    }

    // MARK: - The 07-29 shape

    func testAMorningReSleepDrawsInTheSameNightWithItsGapVisible() throws {
        let nightStart = at(0, 2.883)   // 02:53
        let reSleepStart = at(0, 8.33)  // 08:20
        let rawPile = [
            raw("oura.sleep.sleep_phase_5_min", .text(String(repeating: "2", count: 12)),
                start: nightStart),
            raw("oura.sleep.type", .text("long_sleep"), start: nightStart),
            raw("oura.sleep.sleep_phase_5_min", .text(String(repeating: "2", count: 6)),
                start: reSleepStart),
            raw("oura.sleep.type", .text("late_nap"), start: reSleepStart)
        ]
        let detail = try XCTUnwrap(NightSleepDetail.latest(raw: rawPile, samples: [],
                                                           calendar: calendar))
        let oura = try XCTUnwrap(detail.lanes.first { $0.source == "Oura" })
        XCTAssertEqual(oura.bands.count, 2, "two blocks, one night")
        XCTAssertGreaterThan(oura.bands[1].start, oura.bands[0].end,
                             "the wake between them stays a visible gap")
        XCTAssertEqual(oura.asleepHours, 1.5, accuracy: 0.001)
    }

    func testASiestaIsNotPartOfTheNight() throws {
        let rawPile = [
            raw("oura.sleep.sleep_phase_5_min", .text("222222"), start: at(0, 2)),
            raw("oura.sleep.type", .text("long_sleep"), start: at(0, 2)),
            raw("oura.sleep.sleep_phase_5_min", .text("2222"), start: at(0, 15)),
            raw("oura.sleep.type", .text("late_nap"), start: at(0, 15))
        ]
        let detail = try XCTUnwrap(NightSleepDetail.latest(raw: rawPile, samples: [],
                                                           calendar: calendar))
        let oura = try XCTUnwrap(detail.lanes.first { $0.source == "Oura" })
        XCTAssertEqual(oura.bands.count, 1, "the 3 pm nap stays out of the night")
    }

    /// An 11 pm bedtime and a 3 am one belong to the same wake day — the same
    /// keying the canonical nights table uses.
    func testNightsAreKeyedByWakeDay() {
        XCTAssertEqual(NightSleepDetail.wakeDay(of: at(0, 23), calendar: calendar),
                       calendar.startOfDay(for: at(1, 0)))
        XCTAssertEqual(NightSleepDetail.wakeDay(of: at(1, 3), calendar: calendar),
                       calendar.startOfDay(for: at(1, 0)))
    }

    // MARK: - Window-only sources

    func testAStagelessSourceDrawsOneHonestWindow() throws {
        let day = calendar.startOfDay(for: at(1, 0))
        let samples = [
            HealthMetricSample(type: .sleepOnset, value: -0.3, start: day,
                               source: .appleHealth),
            HealthMetricSample(type: .sleepDurationHours, value: 8.6, start: day,
                               source: .appleHealth)
        ]
        let detail = try XCTUnwrap(NightSleepDetail.latest(raw: [], samples: samples,
                                                           calendar: calendar))
        let lane = try XCTUnwrap(detail.lanes.first)
        XCTAssertFalse(lane.hasStageDetail)
        let band = try XCTUnwrap(lane.bands.first)
        XCTAssertNil(band.stage)
        XCTAssertEqual(band.start, day.addingTimeInterval(-0.3 * 3600),
                       "a negative onset is the evening before")
        XCTAssertEqual(band.hours, 8.6, accuracy: 0.001)
    }

    func testTheLatestNightWins() throws {
        let rawPile = [
            raw("oura.sleep.sleep_phase_5_min", .text("2222"), start: at(0, 2)),
            raw("oura.sleep.sleep_phase_5_min", .text("3333"), start: at(5, 2))
        ]
        let detail = try XCTUnwrap(NightSleepDetail.latest(raw: rawPile, samples: [],
                                                           calendar: calendar))
        XCTAssertEqual(detail.night, calendar.startOfDay(for: at(5, 0)))
    }

    func testNothingRecordedIsNil() {
        XCTAssertNil(NightSleepDetail.latest(raw: [], samples: [], calendar: calendar))
    }
}
