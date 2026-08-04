import XCTest
@testable import InsightKit

/// **An Apple night drew as a flat grey bar while an Oura night showed its
/// hypnogram**, and the reader reported it. Apple has recorded core/deep/REM
/// since iOS 16 and their own export carries stage minutes on 132 nights — the
/// segments were fetched, mapped, handed to `SleepNights` for the nightly
/// totals, and then dropped, so this type had nothing to build a lane from and
/// fell through to `windowLanes`, which draws one `stage: nil` band.
final class AppleSleepStagesTests: XCTestCase {

    private let cal = TestClock.utc

    private func segment(_ kind: SleepSegment.Kind, fromHour: Double, hours: Double,
                         device: String = "Apple Watch") -> RawMetricSample {
        let base = cal.startOfDay(for: TestClock.now).addingTimeInterval(-24 * 3600)
        let start = base.addingTimeInterval(fromHour * 3600)
        return RawMetricSample(identifier: NightSleepDetail.appleSegmentIdentifier,
                               displayName: "Sleep stage",
                               value: .text(kind.rawValue), unit: "",
                               start: start,
                               end: start.addingTimeInterval(hours * 3600),
                               source: MetricSource(id: "apple_health/\(device)",
                                                    displayName: device))
    }

    /// The defect, directly: stages in, stages out.
    func testAnAppleNightDrawsItsStagesRatherThanOneGreyBand() throws {
        let detail = try XCTUnwrap(NightSleepDetail.latest(
            raw: [segment(.core, fromHour: 23, hours: 2),
                  segment(.deep, fromHour: 25, hours: 1.5),
                  segment(.rem, fromHour: 26.5, hours: 1)],
            samples: [], calendar: cal))
        let lane = try XCTUnwrap(detail.lanes.first)
        XCTAssertEqual(lane.bands.count, 3)
        XCTAssertNil(lane.bands.first { $0.stage == nil },
                     "a band with no stage is the flat grey bar this fixes")
    }

    /// `core` is drawn as **Light**, matching Oura's lane rather than Apple's
    /// own wording — the two lanes exist to be compared, and the same sleep
    /// under two different labels defeats that.
    func testCoreIsDrawnAsLightSoTheTwoLanesAreComparable() throws {
        let detail = try XCTUnwrap(NightSleepDetail.latest(
            raw: [segment(.core, fromHour: 23, hours: 2)], samples: [], calendar: cal))
        XCTAssertEqual(try XCTUnwrap(detail.lanes.first?.bands.first).stage, .light)
    }

    /// Real sleep of unknown stage is still sleep. Dropping it would leave a
    /// hole in a night that was genuinely slept.
    func testUnspecifiedSleepIsDrawnRatherThanDropped() throws {
        let detail = try XCTUnwrap(NightSleepDetail.latest(
            raw: [segment(.unspecified, fromHour: 23, hours: 3)], samples: [], calendar: cal))
        XCTAssertEqual(try XCTUnwrap(detail.lanes.first?.bands.first).stage, .light)
    }

    /// `inBed` is time in bed, not a stage. Drawing it would lay a band under
    /// the whole night that every stage colour then sits on top of.
    func testTimeInBedIsNotDrawnAsAStage() throws {
        let detail = NightSleepDetail.latest(
            raw: [segment(.inBed, fromHour: 22.5, hours: 8)], samples: [], calendar: cal)
        XCTAssertNil(detail, "in-bed alone is not a hypnogram and must not produce a lane")
    }

    /// Two devices writing sleep into Health get their own lanes. Splicing a
    /// watch's night onto a ring's would invent a night neither recorded.
    func testEachWritingDeviceGetsItsOwnLane() throws {
        let detail = try XCTUnwrap(NightSleepDetail.latest(
            raw: [segment(.core, fromHour: 23, hours: 2, device: "Apple Watch"),
                  segment(.deep, fromHour: 23.5, hours: 1, device: "Oura Ring")],
            samples: [], calendar: cal))
        XCTAssertEqual(detail.lanes.count, 2)
    }

    /// **The grey fallback must not draw underneath the stages.** Both are
    /// derived from the same night, so without suppression the lane list would
    /// carry the hypnogram and a flat bar for the same device.
    func testTheWindowFallbackIsSuppressedForASourceThatHasStages() throws {
        let night = cal.startOfDay(for: TestClock.now).addingTimeInterval(-24 * 3600)
        let device = MetricSource(id: "apple_health/Apple Watch", displayName: "Apple Watch")
        let samples = [
            HealthMetricSample(type: .sleepOnset, value: -1, start: night, source: device),
            HealthMetricSample(type: .sleepDurationHours, value: 7, start: night, source: device)
        ]
        let detail = try XCTUnwrap(NightSleepDetail.latest(
            raw: [segment(.core, fromHour: 23, hours: 2),
                  segment(.deep, fromHour: 25, hours: 2)],
            samples: samples, calendar: cal))
        let watchLanes = detail.lanes.filter { $0.source == "Apple Watch" }
        XCTAssertEqual(watchLanes.count, 1,
                       "the stage lane and the grey window band both drew for one device")
        XCTAssertNil(try XCTUnwrap(watchLanes.first).bands.first { $0.stage == nil })
    }
}
