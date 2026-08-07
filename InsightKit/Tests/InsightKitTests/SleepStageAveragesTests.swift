import XCTest
@testable import InsightKit

/// The arithmetic behind "A typical night" (backlog P22). Every case here is a
/// way the average could lie about a stretch of nights, which is exactly what a
/// mean is good at.
final class SleepStageAveragesTests: XCTestCase {

    private let calendar = Calendar.current

    private var midnight: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
    }
    private func day(_ offset: Int) -> Date {
        midnight.addingTimeInterval(Double(offset) * 24 * 3600)
    }

    /// One lane's worth of stage bands, laid end to end from 1 am.
    private func lane(_ source: String, night: Date,
                      _ stages: [(NightSleepDetail.Stage?, Double)]) -> NightSleepDetail.Lane {
        var cursor = night.addingTimeInterval(3600)
        var bands: [NightSleepDetail.Band] = []
        for (stage, hours) in stages {
            let end = cursor.addingTimeInterval(hours * 3600)
            bands.append(NightSleepDetail.Band(start: cursor, end: end, stage: stage))
            cursor = end
        }
        return NightSleepDetail.Lane(source: source, bands: bands)
    }

    // MARK: - The denominator

    /// **A source is averaged over the nights it recorded, not over the window.**
    /// The other denominator draws a ring worn two nights in ten as somebody
    /// sleeping ninety minutes a night, which is the single most misleading
    /// thing this chart could do.
    func testASourceIsAveragedOverTheNightsItRecorded() throws {
        let nights = [
            NightSleepDetail(night: day(0), lanes: [
                lane("Oura", night: day(0), [(.deep, 2), (.light, 4), (.rem, 2)]),
                lane("Watch", night: day(0), [(.deep, 1), (.light, 5), (.rem, 1)])
            ]),
            // Nine further nights the watch recorded and the ring did not.
            NightSleepDetail(night: day(1), lanes: [
                lane("Watch", night: day(1), [(.deep, 1), (.light, 5), (.rem, 1)])
            ])
        ]
        let averages = SleepStageAverages.over(nights, since: nil)
        let oura = try XCTUnwrap(averages.rows.first { $0.source == "Oura" })
        XCTAssertEqual(oura.nights, 1)
        XCTAssertEqual(try XCTUnwrap(oura.hoursByStage[.deep]), 2, accuracy: 0.001,
                       "one recorded night, so its own night — not halved by a "
                       + "night it never saw")
        XCTAssertEqual(oura.asleepHours, 8, accuracy: 0.001)

        let watch = try XCTUnwrap(averages.rows.first { $0.source == "Watch" })
        XCTAssertEqual(watch.nights, 2)
        XCTAssertEqual(watch.asleepHours, 7, accuracy: 0.001)
    }

    /// Two sources disagreeing by four hours is the reason this card exists.
    /// Pooling them would resolve that by fiat.
    func testSourcesAreNeverAveragedTogether() throws {
        let nights = [NightSleepDetail(night: day(0), lanes: [
            lane("Oura", night: day(0), [(.light, 4.3)]),
            lane("iPhone", night: day(0), [(nil, 8.5)])
        ])]
        let averages = SleepStageAverages.over(nights, since: nil)
        XCTAssertEqual(averages.rows.count, 2)
        XCTAssertEqual(try XCTUnwrap(averages.rows.first { $0.source == "Oura" }).asleepHours,
                       4.3, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(averages.rows.first { $0.source == "iPhone" }).asleepHours,
                       8.5, accuracy: 0.001)
    }

    // MARK: - The timeframe

    /// `since` is compared against the wake day, the key every sleep surface
    /// files a night under — so the same seven nights are "the past week" here
    /// as everywhere else.
    func testTheWindowExcludesNightsBeforeIt() {
        let nights = (0..<10).map { offset in
            NightSleepDetail(night: day(offset), lanes: [
                lane("Oura", night: day(offset), [(.deep, Double(offset))])
            ])
        }
        let recent = SleepStageAverages.over(nights, since: day(8))
        XCTAssertEqual(recent.nightsCovered, 2)
        XCTAssertEqual(recent.rows.first?.hoursByStage[.deep] ?? 0, 8.5, accuracy: 0.001)

        let all = SleepStageAverages.over(nights, since: nil)
        XCTAssertEqual(all.nightsCovered, 10)
    }

    /// A timeframe with nothing in it is empty, not a row of zeroes. A zero-hour
    /// bar would read as "you slept none", which is a claim about the reader
    /// rather than about the window.
    func testAnEmptyWindowIsEmptyRatherThanZero() {
        let nights = [NightSleepDetail(night: day(0), lanes: [
            lane("Oura", night: day(0), [(.deep, 2)])
        ])]
        let averages = SleepStageAverages.over(nights, since: day(5))
        XCTAssertTrue(averages.isEmpty)
        XCTAssertEqual(averages.nightsCovered, 0)
        XCTAssertNil(averages.span)
    }

    // MARK: - Honesty about stages

    /// **A stageless source has no deep sleep of zero — it has no reading.** A
    /// device reporting only its window contributes to hours asleep and to
    /// nothing else, and says so through `hasStageDetail`.
    func testAStagelessSourceClaimsNoStages() throws {
        let nights = [NightSleepDetail(night: day(0), lanes: [
            lane("iPhone", night: day(0), [(nil, 7)])
        ])]
        let row = try XCTUnwrap(SleepStageAverages.over(nights, since: nil).rows.first)
        XCTAssertFalse(row.hasStageDetail)
        XCTAssertTrue(row.hoursByStage.isEmpty,
                      "absent, not zero — the source never measured a stage")
        XCTAssertEqual(row.asleepHours, 7, accuracy: 0.001)
        XCTAssertTrue(row.stagesInDrawOrder.isEmpty)
    }

    /// Awake time is part of the picture and not part of the sleep — the same
    /// rule `NightSleepDetail.Lane.asleepHours` applies to one night.
    func testAwakeIsChartedButNotCountedAsSleep() throws {
        let nights = [NightSleepDetail(night: day(0), lanes: [
            lane("Oura", night: day(0), [(.deep, 2), (.awake, 1), (.rem, 2)])
        ])]
        let row = try XCTUnwrap(SleepStageAverages.over(nights, since: nil).rows.first)
        XCTAssertEqual(row.asleepHours, 4, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(row.hoursByStage[.awake]), 1, accuracy: 0.001)
    }

    /// Stage-bearing sources sort first, matching the lane order
    /// `NightSleepDetail` draws — so the two charts on the card read the same
    /// way down.
    func testStagedSourcesSortBeforeStagelessOnes() {
        let nights = [NightSleepDetail(night: day(0), lanes: [
            lane("Aaa phone", night: day(0), [(nil, 7)]),
            lane("Zzz ring", night: day(0), [(.deep, 2), (.light, 5)])
        ])]
        let averages = SleepStageAverages.over(nights, since: nil)
        XCTAssertEqual(averages.rows.map(\.source), ["Zzz ring", "Aaa phone"])
    }

    // MARK: - The nights it averages over

    /// `allNights` and `latest` must build the same night, or the chart drawing
    /// one night and the chart averaging many would disagree about what a night
    /// is.
    func testAllNightsAgreesWithLatest() throws {
        func raw(_ identifier: String, _ value: RawValue, start: Date) -> RawMetricSample {
            RawMetricSample(id: UUID(), identifier: identifier, displayName: identifier,
                            value: value, unit: "", start: start, source: .oura)
        }
        var pile: [RawMetricSample] = []
        for offset in 0..<3 {
            let start = day(offset).addingTimeInterval(2 * 3600)
            pile.append(raw("oura.sleep.sleep_phase_5_min",
                            .text(String(repeating: "1", count: 12)), start: start))
            pile.append(raw("oura.sleep.type", .text("long_sleep"), start: start))
        }
        let all = NightSleepDetail.allNights(raw: pile, samples: [], calendar: calendar)
        XCTAssertEqual(all.count, 3)
        XCTAssertEqual(all.map(\.night), all.map(\.night).sorted(), "oldest first")
        XCTAssertEqual(NightSleepDetail.latest(raw: pile, samples: [], calendar: calendar),
                       all.last)
    }
}
