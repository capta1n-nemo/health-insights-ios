import XCTest
@testable import InsightKit

/// Backlog §B5 #34. Every fixture here is shaped like the reader's real
/// `physicalEffort` data rather than like a tidy workout log, because the shape
/// is what the design turns on: **ten-second samples, most days absent, and a
/// worn day covering fifteen hours rather than twenty-four.**
final class EffortIntensityTests: XCTestCase {

    private let now = TestClock.day(0)
    private let calendar = TestClock.utc

    /// Effort samples as Apple writes them: short intervals through the day.
    /// `mets` is applied to every chunk; `chunkMinutes` is the interval length.
    private func effort(daysAgo: Int, mets: Double, minutes: Double,
                        chunkMinutes: Double = 10) -> [HealthMetricSample] {
        guard minutes > 0 else { return [] }
        // The chunks sum to exactly `minutes` whatever length is asked for, so
        // a test can vary the sample length without also varying the total.
        let count = Swift.max(1, Int((minutes / chunkMinutes).rounded()))
        let each = minutes / Double(count)
        return (0..<count).map { index in
            let start = TestClock.day(daysAgo)
                .addingTimeInterval(Double(index) * each * 60)
            return HealthMetricSample(
                type: .physicalEffort, value: mets,
                start: start,
                end: start.addingTimeInterval(each * 60),
                source: .appleHealthDevice("Apple Watch"))
        }
    }

    /// A week with the same split every day, so the arithmetic is checkable by
    /// hand.
    private func week(days: [Int], lightMinutes: Double = 600,
                      moderateMinutes: Double = 0,
                      vigorousMinutes: Double = 0) -> [HealthMetricSample] {
        days.flatMap { day in
            effort(daysAgo: day, mets: 1.5, minutes: lightMinutes)
                + effort(daysAgo: day, mets: 4, minutes: moderateMinutes)
                + effort(daysAgo: day, mets: 8, minutes: vigorousMinutes)
        }
    }

    // MARK: - The bands

    func testTheBandEdgesAreTheCompendiumsOwn() {
        XCTAssertEqual(EffortIntensityModel.Band.of(1), .light)
        XCTAssertEqual(EffortIntensityModel.Band.of(2.99), .light)
        XCTAssertEqual(EffortIntensityModel.Band.of(3), .moderate,
                       "3 METs is the floor of moderate, not the top of light")
        XCTAssertEqual(EffortIntensityModel.Band.of(5.99), .moderate)
        XCTAssertEqual(EffortIntensityModel.Band.of(6), .vigorous)
        XCTAssertEqual(EffortIntensityModel.Band.of(20), .vigorous)
    }

    // MARK: - Minutes, not samples

    func testMinutesComeFromTheIntervalNotTheSampleCount() throws {
        // 81,252 rows over 319 days is the trap the whole model is written
        // around: counting rows would make a fidgety afternoon look like a
        // marathon. 60 minutes of moderate effort is 60 minutes whether it
        // arrives as six ten-minute samples or 360 ten-second ones.
        let coarse = week(days: [1, 2, 3], lightMinutes: 60,
                          moderateMinutes: 60, chunked: 10)
        let fine = week(days: [1, 2, 3], lightMinutes: 60,
                        moderateMinutes: 60, chunked: 1.0 / 6)
        let a = try XCTUnwrap(EffortIntensityModel.evaluate(samples: coarse, now: now,
                                                            calendar: calendar))
        let b = try XCTUnwrap(EffortIntensityModel.evaluate(samples: fine, now: now,
                                                            calendar: calendar))
        XCTAssertEqual(a.moderateMinutes, 180, accuracy: 0.01)
        XCTAssertEqual(b.moderateMinutes, 180, accuracy: 0.01)
        XCTAssertEqual(a.score, b.score, accuracy: 0.001)
    }

    func testAZeroLengthSampleContributesNoTime() throws {
        var samples = week(days: [1, 2, 3], moderateMinutes: 30)
        // A point reading — Apple does write these. It may set the peak; it may
        // not invent a minute.
        samples.append(HealthMetricSample(
            type: .physicalEffort, value: 12,
            start: TestClock.day(1), source: .appleHealthDevice("Apple Watch")))
        let output = try XCTUnwrap(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                                 calendar: calendar))
        XCTAssertEqual(output.moderateMinutes, 90, accuracy: 0.01)
        XCTAssertEqual(output.vigorousMinutes, 0, accuracy: 0.01)
        XCTAssertEqual(output.peakMETs, 12, accuracy: 0.01,
                       "a point reading is still the hardest thing that happened")
    }

    // MARK: - WHO's substitution, which is the reason this model exists

    func testAVigorousMinuteCountsAsTwoModerateOnes() throws {
        let samples = week(days: [1, 2, 3], moderateMinutes: 20, vigorousMinutes: 10)
        let output = try XCTUnwrap(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                                 calendar: calendar))
        XCTAssertEqual(output.moderateMinutes, 60, accuracy: 0.01)
        XCTAssertEqual(output.vigorousMinutes, 30, accuracy: 0.01)
        XCTAssertEqual(output.moderateEquivalentMinutes, 120, accuracy: 0.01)
    }

    /// ⚠️ **The measurement that changed the design.** On the reader's own
    /// export the best week held 392 moderate minutes and 26 vigorous ones.
    /// Scored on vigorous alone that is a poor week against WHO's 75-minute
    /// vigorous floor; scored properly it is past the top of the band. A reader
    /// who exceeds the guideline by walking must not be told they are unfit.
    func testAModerateHeavyWeekIsNotScoredAsUnfit() throws {
        let samples = week(days: [1, 2, 3, 4, 5, 6, 7],
                           moderateMinutes: 56, vigorousMinutes: 3.7)
        let output = try XCTUnwrap(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                                 calendar: calendar))
        XCTAssertEqual(output.moderateMinutes, 392, accuracy: 1)
        XCTAssertEqual(output.vigorousMinutes, 26, accuracy: 1)
        XCTAssertEqual(output.score, 100, accuracy: 0.001,
                       "392 moderate minutes is past the top of the 150–300 band")
        XCTAssertLessThan(
            ActivityDoseModel.score(weeklyMinutes: output.vigorousMinutes), 60,
            "and this is what a vigorous-only score would have said about the same week")
    }

    func testTheCurveIsActivityDosesOwn() {
        // Not a copy of it. Two curves for one published band is how they drift.
        for minutes in stride(from: 0.0, through: 500, by: 25) {
            let samples = week(days: [1, 2, 3], moderateMinutes: minutes / 3)
            let output = EffortIntensityModel.evaluate(samples: samples, now: now,
                                                       calendar: calendar)
            XCTAssertEqual(output?.score ?? -1,
                           ActivityDoseModel.score(weeklyMinutes: minutes),
                           accuracy: 0.5)
        }
    }

    // MARK: - The coverage gate

    func testAWatchWornTwiceInAWeekCannotBeJudged() {
        // Eight of the reader's last twelve weeks hold zero recorded days and a
        // ninth holds three. A weekly total from one worn day reads as "you did
        // almost nothing", when what happened is that the watch was in a drawer.
        let samples = week(days: [2, 5], moderateMinutes: 40)
        XCTAssertNil(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                   calendar: calendar))
    }

    func testTheGateIsSharedWithTheExerciseMinuteDose() {
        XCTAssertEqual(EffortIntensityModel.minimumRecordedDays,
                       ActivityDoseModel.minimumRecordedDays,
                       "one judgement about one window — two floors would mean the card changed its mind about 'enough' depending on which input it used")
    }

    func testLastFortnightsTrainingIsOutsideThisWeek() throws {
        var samples = week(days: [1, 2, 3], moderateMinutes: 20)
        samples += week(days: [20, 21, 22], moderateMinutes: 300)
        let output = try XCTUnwrap(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                                 calendar: calendar))
        XCTAssertEqual(output.moderateMinutes, 60, accuracy: 0.01)
    }

    // MARK: - What the reader is told about coverage

    func testAPartlyWornDayIsReportedRatherThanScaledUp() throws {
        // p10 of the reader's recorded days is 301 minutes of wear, p90 is
        // 1,362. Scaling a five-hour day up to a full one would credit activity
        // nobody measured.
        let samples = week(days: [1, 2, 3], lightMinutes: 240, moderateMinutes: 30)
        let output = try XCTUnwrap(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                                 calendar: calendar))
        XCTAssertEqual(output.wornMinutes, 810, accuracy: 1)
        XCTAssertEqual(output.moderateEquivalentMinutes, 90, accuracy: 1,
                       "90 measured minutes stays 90, not 90 grossed up to a full day")
        XCTAssertTrue(EffortIntensityModel.coveragePhrase(output).contains("3 of the last 7 days"))
    }

    func testAWeekWithNoActiveTimeHasNoVigorousShareRatherThanZeroPercent() throws {
        let samples = week(days: [1, 2, 3], lightMinutes: 600)
        let output = try XCTUnwrap(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                                 calendar: calendar))
        XCTAssertNil(output.vigorousShare,
                     "'no active time' and '0% of your active time was hard' are different claims")
    }

    func testThePhraseNamesTheSplitRatherThanRestatingTheTotal() throws {
        let samples = week(days: [1, 2, 3, 4], moderateMinutes: 50, vigorousMinutes: 10)
        let output = try XCTUnwrap(EffortIntensityModel.evaluate(samples: samples, now: now,
                                                                 calendar: calendar))
        let phrase = EffortIntensityModel.phrase(output)
        XCTAssertTrue(phrase.contains("moderate"))
        XCTAssertTrue(phrase.contains("vigorous"))
        XCTAssertTrue(phrase.contains("guideline band"))
    }

    // MARK: - The daily split behind the chart

    func testADayWithNoDataIsAbsentRatherThanZero() {
        // A zero bar and an unworn watch look identical on a chart, and only
        // one of them is a rest day.
        let samples = week(days: [1, 3, 5], moderateMinutes: 30)
        let split = EffortIntensityModel.dailySplit(samples: samples, days: 7,
                                                    now: now, calendar: calendar)
        XCTAssertEqual(split.count, 3)
        XCTAssertTrue(split.allSatisfy { $0.moderateMinutes > 0 })
    }

    func testTheSplitIsOldestFirst() {
        let samples = week(days: [1, 3, 5], moderateMinutes: 30)
        let split = EffortIntensityModel.dailySplit(samples: samples, days: 7,
                                                    now: now, calendar: calendar)
        XCTAssertEqual(split.map(\.date), split.map(\.date).sorted())
    }

    // MARK: - On the card

    private func profile(age: Double = 40, male: Bool = true) -> UserHealthProfile {
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-age * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: now))
        return p
    }

    private func vo2History() -> [HealthMetricSample] {
        (0..<8).map {
            HealthMetricSample(type: .vo2Max, value: 40,
                               start: TestClock.day($0 * 7),
                               source: .appleHealthDevice("Apple Watch"))
        }
    }

    func testEffortSupersedesTheExerciseMinuteRatherThanJoiningIt() throws {
        // Both inputs present. Two WHO terms would count one afternoon's
        // walking twice, so exactly one of them may carry weight.
        var samples = vo2History()
        samples += week(days: [1, 2, 3, 4], moderateMinutes: 50)
        for day in [1, 2, 3, 4] {
            samples.append(HealthMetricSample(
                type: .exerciseMinutes, value: 50, start: TestClock.day(day),
                source: .appleHealthDevice("Apple Watch")))
        }
        let result = FitnessInsight().evaluate(samples: samples, profile: profile(), now: now)
        XCTAssertTrue(result.contributors.contains { $0.metric == .physicalEffort },
                      "the intensity-carrying input wins when it is available")
        XCTAssertEqual(result.contributors.filter { $0.metric == .exerciseMinutes }.count, 0,
                       "and the exercise-minute dose must not also be weighted")
    }

    func testTheExerciseMinuteIsStillThereWhenEffortIsTooThin() throws {
        var samples = vo2History()
        // One worn day of effort — below the gate.
        samples += week(days: [1], moderateMinutes: 50)
        for day in [1, 2, 3, 4] {
            samples.append(HealthMetricSample(
                type: .exerciseMinutes, value: 50, start: TestClock.day(day),
                source: .appleHealthDevice("Apple Watch")))
        }
        let result = FitnessInsight().evaluate(samples: samples, profile: profile(), now: now)
        XCTAssertTrue(result.contributors.contains { $0.metric == .exerciseMinutes },
                      "nothing about the card changes on a week with too little effort data")
    }

    func testTheCoverageCaveatReachesTheCard() throws {
        var samples = vo2History()
        samples += week(days: [1, 2, 3, 4], moderateMinutes: 50)
        let result = FitnessInsight().evaluate(samples: samples, profile: profile(), now: now)
        XCTAssertTrue(result.driverLines.contains { $0.text.contains("of the last 7 days") },
                      "a weekly total from four worn days is not the same claim as one from seven, and the card has to say which it is")
    }

    /// Backlog §B5 #35: distance and flights are Fitness sections, which in
    /// this app means candidates on the Fitness card — that is what puts them
    /// in the overlay, "How far from your normal" and "What goes into this".
    func testDistanceAndFlightsAreFitnessSignals() {
        let candidates = Set(FitnessInsight().candidateMetrics)
        XCTAssertTrue(candidates.contains(.distanceWalkingRunning))
        XCTAssertTrue(candidates.contains(.flightsClimbed))
        XCTAssertTrue(candidates.contains(.physicalEffort))
    }

    /// The version bump is the whole point of `modelVersion`: the dose term can
    /// now be computed from a different input, so the same week returns a
    /// different number and old recorded scores are not comparable.
    func testTheFitnessModelVersionMovedWithTheScore() {
        XCTAssertEqual(InsightID.fitness.modelVersion, "fitness-v2")
    }
}

private extension EffortIntensityTests {
    /// The `chunked:` variant, so one test can prove sample *length* does not
    /// change the answer.
    func week(days: [Int], lightMinutes: Double = 600,
              moderateMinutes: Double = 0, vigorousMinutes: Double = 0,
              chunked: Double) -> [HealthMetricSample] {
        days.flatMap { day in
            effort(daysAgo: day, mets: 1.5, minutes: lightMinutes, chunkMinutes: chunked)
                + effort(daysAgo: day, mets: 4, minutes: moderateMinutes, chunkMinutes: chunked)
                + effort(daysAgo: day, mets: 8, minutes: vigorousMinutes, chunkMinutes: chunked)
        }
    }
}
