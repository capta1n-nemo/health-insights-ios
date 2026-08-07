import XCTest
@testable import InsightKit

/// Backlog D46 — the reader's transparency rule: *"it needs to be mentioned
/// appropriately for transparency, so users know why things are - or are not
/// showing in the app."*
final class CoverageGateTests: XCTestCase {

    private let now = TestClock.day(0)

    // MARK: - The sentence

    func testNothingRecordedSaysWhatToStartDoing() throws {
        let gate = CoverageGate(need: 3, have: 0, unit: "day",
                                unlocks: "this can total your week")
        let sentence = try XCTUnwrap(gate.sentence)
        XCTAssertTrue(sentence.contains("3 days"))
        XCTAssertTrue(sentence.contains("this can total your week"))
    }

    /// The number that makes somebody carry on is **how many more**, not how
    /// many there are — so it has to be in the sentence, not inferable from it.
    func testPartwaySaysHowManyMore() throws {
        let gate = CoverageGate(need: 5, have: 3, unit: "worn day",
                                unlocks: "the dose can be judged")
        let sentence = try XCTUnwrap(gate.sentence)
        XCTAssertTrue(sentence.contains("3 of 5"))
        XCTAssertTrue(sentence.contains("2 more"))
    }

    /// ⚠️ A card that keeps naming a threshold it has already cleared is
    /// nagging, and this app does not nag.
    func testAMetGateSaysNothingAtAll() {
        let gate = CoverageGate(need: 3, have: 3, unit: "marker", unlocks: "x")
        XCTAssertNil(gate.sentence)
        XCTAssertNil(gate.shortLabel)
        XCTAssertTrue(gate.isMet)
        XCTAssertEqual(gate.remaining, 0)
    }

    func testOvershootIsStillMetAndStillSilent() {
        let gate = CoverageGate(need: 3, have: 90, unit: "day", unlocks: "x")
        XCTAssertNil(gate.sentence)
        XCTAssertEqual(gate.remaining, 0)
        XCTAssertEqual(gate.progress, 1)
    }

    func testOneOfSomethingIsNotPluralised() throws {
        let gate = CoverageGate(need: 1, have: 0, unit: "reading", unlocks: "x")
        XCTAssertTrue(try XCTUnwrap(gate.sentence).contains("1 reading"))
    }

    func testIfShortIsNilWhenTheRequirementIsMet() {
        XCTAssertNil(CoverageGate.ifShort(need: 2, have: 2, unit: "day", unlocks: "x"))
        XCTAssertNotNil(CoverageGate.ifShort(need: 2, have: 1, unit: "day", unlocks: "x"))
    }

    func testProgressIsAFractionAndNeverExceedsOne() {
        XCTAssertEqual(CoverageGate(need: 4, have: 1, unit: "d", unlocks: "x").progress,
                       0.25, accuracy: 0.001)
        XCTAssertEqual(CoverageGate(need: 0, have: 0, unit: "d", unlocks: "x").progress, 1,
                       "a requirement of zero is met by definition, not a division by zero")
    }

    // MARK: - Wired into the models a reader actually hits

    private func effort(days: [Int], minutes: Double = 40) -> [HealthMetricSample] {
        days.map { day in
            let start = TestClock.day(day)
            return HealthMetricSample(type: .physicalEffort, value: 4,
                                      start: start,
                                      end: start.addingTimeInterval(minutes * 60),
                                      source: .appleHealthDevice("Apple Watch"))
        }
    }

    func testTheEffortDoseSaysHowManyWornDaysItStillNeeds() throws {
        // Two worn days against a floor of three: the model returns no figure,
        // and until now that was all the reader got.
        let samples = effort(days: [1, 2])
        XCTAssertNil(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                   calendar: TestClock.utc))
        let gate = try XCTUnwrap(EffortIntensityModel.coverage(
            samples: samples, now: now, calendar: TestClock.utc))
        XCTAssertEqual(gate.have, 2)
        XCTAssertEqual(gate.need, EffortIntensityModel.minimumRecordedDays)
        XCTAssertTrue(try XCTUnwrap(gate.sentence).contains("1 more"))
    }

    func testTheEffortDoseGoesQuietOnceTheWeekIsCovered() {
        let samples = effort(days: [1, 2, 3, 4])
        XCTAssertNotNil(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                      calendar: TestClock.utc))
        XCTAssertNil(EffortIntensityModel.coverage(samples: samples, now: now,
                                                   calendar: TestClock.utc),
                     "the figure is there, so there is nothing to explain")
    }

    func testTheTrajectoryCountsReadingsRatherThanTellingSomebodyToWait() throws {
        // Counting the six-week span would be true and useless — nobody can
        // act on the calendar. The reading count is the actionable half.
        let samples = (0..<2).map {
            HealthMetricSample(type: .vo2Max, value: 40,
                               start: TestClock.day($0 * 7),
                               source: .appleHealthDevice("Apple Watch"))
        }
        let gate = try XCTUnwrap(VO2Trajectory.coverage(samples: samples, now: now))
        XCTAssertEqual(gate.have, 2)
        XCTAssertEqual(gate.need, VO2Trajectory.minimumReadings)
        XCTAssertTrue(try XCTUnwrap(gate.sentence).contains("2 more"))
    }

    func testAStaleReadingDoesNotCountTowardTheTrajectory() throws {
        // A slope fitted to readings that stopped six months ago describes a
        // fitness level the reader may no longer have — the model's own rule,
        // so the gate has to agree with it or the two will disagree on screen.
        let samples = (0..<6).map {
            HealthMetricSample(type: .vo2Max, value: 40,
                               start: TestClock.day(200 + $0),
                               source: .appleHealthDevice("Apple Watch"))
        }
        let gate = try XCTUnwrap(VO2Trajectory.coverage(samples: samples, now: now))
        XCTAssertEqual(gate.have, 0)
    }
}
