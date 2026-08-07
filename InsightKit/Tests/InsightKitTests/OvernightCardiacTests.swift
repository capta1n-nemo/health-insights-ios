import XCTest
@testable import InsightKit

/// The arithmetic behind the two sections that finally read the heartbeat stream
/// recorded during sleep (backlog S10 and B3-20).
///
/// Every assertion here is about a claim the screen makes: which readings belong
/// to which night, what "settled" means, and — the one that matters most — when
/// the type refuses to draw a typical curve at all.
final class OvernightCardiacTests: XCTestCase {

    private let calendar = Calendar.current

    private var midnight: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000))
    }

    private func at(_ day: Int, _ hour: Double) -> Date {
        midnight.addingTimeInterval((Double(day) * 24 + hour) * 3600)
    }

    private func sample(_ type: MetricType, _ value: Double, at date: Date) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value, start: date, end: date,
                           source: .appleHealthDevice("Apple Watch"))
    }

    /// A night from 23:00 on `day` to 07:00 the next morning, keyed to the wake
    /// day the rest of the app uses.
    private func window(_ day: Int) -> OvernightCardiac.NightWindow {
        OvernightCardiac.NightWindow(night: calendar.startOfDay(for: at(day + 1, 0)),
                                     window: at(day, 23)...at(day + 1, 7))
    }

    /// A descending heart rate: 70 at lights-out, floor of 50 after two hours,
    /// flat after that. One reading every ten minutes.
    private func descendingNight(_ day: Int, floor: Double = 50, opening: Double = 70)
    -> [HealthMetricSample] {
        stride(from: 0.0, to: 8.0, by: 1.0 / 6).map { hours in
            let value = hours >= 2 ? floor : opening - (opening - floor) * (hours / 2)
            return sample(.heartRate, value, at: at(day, 23).addingTimeInterval(hours * 3600))
        }
    }

    // MARK: - Which readings belong to which night

    func testOnlyReadingsInsideTheWindowAreCounted() throws {
        let readings = [
            sample(.heartRate, 90, at: at(0, 20)),     // before bed
            sample(.heartRate, 55, at: at(0, 23.5)),
            sample(.heartRate, 52, at: at(1, 3)),
            sample(.heartRate, 51, at: at(1, 5)),
            sample(.heartRate, 53, at: at(1, 6)),
            sample(.heartRate, 54, at: at(1, 6.5)),
            sample(.heartRate, 56, at: at(1, 6.9)),
            sample(.heartRate, 88, at: at(1, 10))      // after getting up
        ].sorted { $0.start < $1.start }

        let out = OvernightCardiac.build(windows: [window(0)], samples: readings)
        let night = try XCTUnwrap(out.nights.first)
        let heart = try XCTUnwrap(night.heartRate)
        XCTAssertEqual(heart.count, 6, "the daytime readings either side are not the night")
        XCTAssertEqual(heart.highest, 56)
        XCTAssertEqual(heart.lowest, 51)
    }

    func testTooFewReadingsProduceNoSummaryRatherThanAThinOne() throws {
        let readings = [sample(.heartRate, 55, at: at(0, 23.5)),
                        sample(.heartRate, 52, at: at(1, 3))]
        let out = OvernightCardiac.build(windows: [window(0)], samples: readings)
        XCTAssertNil(try XCTUnwrap(out.nights.first).heartRate,
                     "two readings cannot describe a night")
    }

    /// Windows may touch; a reading inside both genuinely happened during both,
    /// and the sweep must not consume it for the first one it meets.
    func testAReadingInTwoWindowsIsCountedInBoth() {
        let shared = at(1, 7)
        let overlapping = [
            OvernightCardiac.NightWindow(night: at(1, 0), window: at(0, 23)...at(1, 7)),
            OvernightCardiac.NightWindow(night: at(2, 0), window: at(1, 7)...at(1, 12))
        ]
        let out = OvernightCardiac.assign([sample(.heartRate, 60, at: shared)],
                                          to: overlapping)
        XCTAssertEqual(out.map(\.count), [1, 1])
    }

    // MARK: - The curve

    func testTheCurveIsBinnedFromLightsOutNotFromMidnight() throws {
        let out = OvernightCardiac.build(windows: [window(0)], samples: descendingNight(0))
        let curve = try XCTUnwrap(out.nights.first).heartRateCurve
        let first = try XCTUnwrap(curve.first)
        XCTAssertEqual(first.hours, OvernightCardiac.bucket / 3600 / 2, accuracy: 0.001,
                       "the first bin is centred inside the first twenty minutes")
        XCTAssertGreaterThan(first.value, curve[curve.count - 1].value,
                             "a descending night descends")
    }

    func testABinTakesTheMedianSoOneRollOverDoesNotDrawASpike() throws {
        var readings = descendingNight(0)
        readings.append(sample(.heartRate, 145, at: at(0, 23.05)))
        readings.sort { $0.start < $1.start }
        let out = OvernightCardiac.build(windows: [window(0)], samples: readings)
        let first = try XCTUnwrap(try XCTUnwrap(out.nights.first).heartRateCurve.first)
        XCTAssertLessThan(first.value, 80, "a single 145 must not become the bin")
    }

    // MARK: - Settling

    func testSettlingIsWhereTheRateFirstReachesTheFloorNotTheMinimumItself() throws {
        let out = OvernightCardiac.build(windows: [window(0)], samples: descendingNight(0))
        let settled = try XCTUnwrap(try XCTUnwrap(out.nights.first).settledAfterHours)
        XCTAssertEqual(settled, 1.83, accuracy: 0.35,
                       "70 → 50 over two hours reaches within a tenth just before two")
    }

    func testANightThatNeverCameDownHasNoSettlingTime() throws {
        let flat = stride(from: 0.0, to: 8.0, by: 1.0 / 6).map { hours in
            sample(.heartRate, 60, at: at(0, 23).addingTimeInterval(hours * 3600))
        }
        let out = OvernightCardiac.build(windows: [window(0)], samples: flat)
        XCTAssertNil(try XCTUnwrap(out.nights.first).settledAfterHours,
                     "reporting \"settled immediately\" for a night with no descent "
                         + "would be the opposite of the truth")
    }

    // MARK: - The typical curve refuses to be built from too little

    func testNoTypicalCurveBelowTheFloor() {
        let windows = (0..<4).map { window($0) }
        let readings = (0..<4).flatMap { descendingNight($0) }.sorted { $0.start < $1.start }
        let out = OvernightCardiac.build(windows: windows, samples: readings)
        let target = try? XCTUnwrap(out.nights.last).night
        XCTAssertTrue(out.typicalHeartRate(excluding: target ?? Date()).isEmpty)
        XCTAssertNotNil(out.typicalCoverage(before: target ?? Date()),
                        "and it says how many more nights it needs")
    }

    func testATypicalCurveExcludesTheNightBeingDrawn() throws {
        // Ten ordinary nights, then one wildly different one.
        var readings = (0..<10).flatMap { descendingNight($0) }
        readings += descendingNight(10, floor: 80, opening: 95)
        readings.sort { $0.start < $1.start }
        let out = OvernightCardiac.build(windows: (0...10).map { window($0) },
                                         samples: readings)
        let last = try XCTUnwrap(out.nights.last)
        let band = out.typicalHeartRate(excluding: last.night)
        XCTAssertFalse(band.isEmpty)
        let lateBand = try XCTUnwrap(band.last)
        XCTAssertEqual(lateBand.median, 50, accuracy: 1,
                       "the odd night must not have pulled the band it is judged against")
        XCTAssertEqual(lateBand.nights, 10)
    }

    // MARK: - Coverage, and the trend

    func testHRVCoverageIsSilentOnceItIsMet() {
        let windows = (0..<12).map { window($0) }
        let readings = (0..<12).flatMap { day in
            (0..<8).map { step in
                sample(.heartRateVariabilitySDNN, 60 + Double(step),
                       at: at(day, 23).addingTimeInterval(Double(step) * 3600))
            }
        }.sorted { $0.start < $1.start }
        let out = OvernightCardiac.build(windows: windows, samples: readings)
        XCTAssertEqual(out.hrvNightly.count, 12)
        XCTAssertNil(out.hrvCoverage, "a met gate says nothing")
    }

    func testAFlatSeriesIsNotCalledADrift() throws {
        let points = (0..<20).map {
            OvernightCardiac.NightlyPoint(night: at($0, 0), value: 60 + Double($0 % 3))
        }
        let trend = try XCTUnwrap(OvernightCardiac.trend(points))
        XCTAssertFalse(trend.isMeaningful)
    }
}
