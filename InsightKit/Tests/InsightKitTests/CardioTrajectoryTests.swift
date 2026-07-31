import XCTest
@testable import InsightKit

private let reference = Date(timeIntervalSince1970: 1_700_000_000)
private func day(_ index: Int) -> Date { reference.addingTimeInterval(Double(index) * 86_400) }

/// Bucketing fixtures are pinned to UTC so a runner's local week start can't
/// shift which week a reading lands in.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func vo2Weekly(_ values: [Double], source: MetricSource = .appleHealth) -> [HealthMetricSample] {
    values.enumerated().map { index, value in
        HealthMetricSample(type: .vo2Max, value: value, start: day(index * 7), source: source)
    }
}

/// A year of weekly readings moving linearly from `from` to `to`.
private func linearYear(from start: Double, to end: Double) -> [HealthMetricSample] {
    let weeks = 52
    return vo2Weekly((0..<weeks).map { index in
        start + (end - start) * Double(index) / Double(weeks - 1)
    })
}

private let afterAYear = day(52 * 7)

final class VO2TrajectoryTests: XCTestCase {

    func testAgeTypicalDeclineComesFromTheNormLine() {
        // The male norm line falls a flat 0.4 mL/kg·min per year.
        XCTAssertEqual(VO2Trajectory.ageTypicalChangePerYear(age: 45, sex: .male),
                       -0.4, accuracy: 1e-9)
        // The female line is shallower in places; at 45 it straddles two segments.
        XCTAssertEqual(VO2Trajectory.ageTypicalChangePerYear(age: 45, sex: .female),
                       -0.35, accuracy: 1e-9)
        // Always a decline, at every reportable age and for both sexes.
        for sex in BiologicalSex.allCases {
            for age in [25.0, 40.0, 55.0, 70.0] {
                XCTAssertLessThan(VO2Trajectory.ageTypicalChangePerYear(age: age, sex: sex), 0)
            }
        }
    }

    func testRisingFitnessReadsAsImproving() {
        let output = VO2Trajectory.evaluate(samples: linearYear(from: 38, to: 40),
                                           age: 45, sex: .male, now: afterAYear,
                                           calendar: utc)!
        XCTAssertEqual(output.direction, .improving)
        // The window is 357 days, so a 2-point rise annualises slightly above 2.
        XCTAssertEqual(output.perYear, 2, accuracy: 0.1)
        XCTAssertEqual(output.netPerYear, 2.4, accuracy: 0.1)       // 2 gained + 0.4 not lost
        XCTAssertGreaterThan(output.projectedIn12Months, output.smoothed)
        XCTAssertGreaterThan(output.fitnessYearsGained, 0)
        XCTAssertEqual(output.readings, 52)
        XCTAssertEqual(output.spanDays, 357, accuracy: 0.5)
    }

    func testFlatFitnessIsAGainBecauseAgeingIsNot() {
        // The point of the whole insight: holding level beats the age-typical
        // drift, so it must not read as a failure.
        let output = VO2Trajectory.evaluate(samples: linearYear(from: 40, to: 40),
                                           age: 45, sex: .male, now: afterAYear,
                                           calendar: utc)!
        XCTAssertEqual(output.direction, .holding)
        XCTAssertEqual(output.perYear, 0, accuracy: 1e-6)
        XCTAssertEqual(output.netPerYear, 0.4, accuracy: 1e-6)
        XCTAssertEqual(output.residualSD, 0, accuracy: 1e-6)
        // The gain lives in `netPerYear`. Fitness age itself doesn't move, and
        // pretending otherwise would count the same thing twice.
        XCTAssertEqual(output.fitnessYearsGained, 0, accuracy: 1e-6)
        XCTAssertEqual(output.fitnessAgeNow, 45, accuracy: 0.01)   // norm VO₂max for 45
    }

    func testFallingFitnessSeparatesAgeingFromTheRest() {
        let output = VO2Trajectory.evaluate(samples: linearYear(from: 42, to: 39),
                                           age: 45, sex: .male, now: afterAYear,
                                           calendar: utc)!
        XCTAssertEqual(output.direction, .declining)
        XCTAssertEqual(output.perYear, -3, accuracy: 0.1)
        XCTAssertEqual(output.netPerYear, -2.6, accuracy: 0.1)      // ageing explains only 0.4
        XCTAssertLessThan(output.fitnessYearsGained, 0)
    }

    func testProjectionNeverGoesNegative() {
        // A steep decline extrapolated forward must not predict a negative VO₂max.
        let output = VO2Trajectory.evaluate(samples: linearYear(from: 20, to: 4),
                                           age: 60, sex: .female, now: afterAYear,
                                           calendar: utc)!
        XCTAssertGreaterThanOrEqual(output.projectedIn12Months, 0)
    }

    func testTooLittleHistoryIsNoTrajectory() {
        // Three readings, and a fortnight's span: both below the floor.
        XCTAssertNil(VO2Trajectory.evaluate(samples: vo2Weekly([40, 41, 42]),
                                            age: 45, sex: .male, now: day(21), calendar: utc))
        let dense = (0..<8).map { index in
            HealthMetricSample(type: .vo2Max, value: 40, start: day(index), source: .appleHealth)
        }
        XCTAssertNil(VO2Trajectory.evaluate(samples: dense, age: 45, sex: .male,
                                            now: day(9), calendar: utc))
    }

    func testStaleHistoryIsNoCurrentTrajectory() {
        // A year of good readings that stopped a year ago describes a fitness
        // level this person may no longer have.
        let samples = linearYear(from: 38, to: 40)
        XCTAssertNotNil(VO2Trajectory.evaluate(samples: samples, age: 45, sex: .male,
                                               now: afterAYear, calendar: utc))
        XCTAssertNil(VO2Trajectory.evaluate(samples: samples, age: 45, sex: .male,
                                            now: afterAYear.addingTimeInterval(200 * 86_400),
                                            calendar: utc))
    }

    func testDuplicatedSourcesDoNotWeightTheSlope() {
        // The same watch arriving directly and via Apple Health is one series.
        let direct = vo2Weekly([38, 39, 40, 41, 42, 43, 44, 45], source: .oura)
        let mirrored = vo2Weekly([38, 39, 40, 41, 42, 43, 44, 45],
                                 source: .appleHealthDevice("Oura"))
        let single = VO2Trajectory.evaluate(samples: direct, age: 45, sex: .male,
                                            now: day(60), calendar: utc)!
        let doubled = VO2Trajectory.evaluate(samples: direct + mirrored, age: 45, sex: .male,
                                             now: day(60), calendar: utc)!
        XCTAssertEqual(doubled.readings, single.readings)
        XCTAssertEqual(doubled.perYear, single.perYear, accuracy: 1e-9)
    }

    // MARK: - "What would move it"

    /// Twelve weeks alternating between busy and light, with fitness tracking it.
    private func alternatingWeeks(energyHigh: Double, energyLow: Double,
                                  vo2High: Double, vo2Low: Double,
                                  energySources: [MetricSource] = [.appleHealth]) -> [HealthMetricSample] {
        var samples: [HealthMetricSample] = []
        for week in 0..<12 {
            let busy = week % 2 == 0
            samples.append(HealthMetricSample(type: .vo2Max, value: busy ? vo2High : vo2Low,
                                              start: day(week * 7), source: .appleHealth))
            for source in energySources {
                samples.append(HealthMetricSample(type: .activeEnergyBurned,
                                                  value: busy ? energyHigh : energyLow,
                                                  start: day(week * 7), source: source))
            }
        }
        return samples
    }

    func testBusierWeeksContrastComesFromTheirOwnData() {
        let samples = alternatingWeeks(energyHigh: 2500, energyLow: 1200,
                                       vo2High: 42, vo2Low: 39)
        let output = VO2Trajectory.evaluate(samples: samples, age: 45, sex: .male,
                                            now: day(12 * 7), calendar: utc)!
        let contrast = output.volume!
        XCTAssertEqual(contrast.metric, .activeEnergyBurned)
        XCTAssertEqual(contrast.weeksCompared, 12)
        XCTAssertEqual(contrast.vo2WhenBusier, 42, accuracy: 1e-9)
        XCTAssertEqual(contrast.vo2WhenLighter, 39, accuracy: 1e-9)
        XCTAssertEqual(contrast.difference, 3, accuracy: 1e-9)
        // And it surfaces as a lever drawn from their history, not general advice.
        XCTAssertTrue(output.levers.contains { $0.isPersonal && $0.title.contains("busier weeks") })
    }

    func testWeeklyTotalsTakeOneSourceRatherThanSummingThem() {
        // Summing across sources would double-count a walk recorded by both the
        // watch on your wrist and the phone in your pocket.
        let samples = alternatingWeeks(
            energyHigh: 2500, energyLow: 1200, vo2High: 42, vo2Low: 39,
            energySources: [.appleHealthDevice("Apple Watch"), .appleHealthDevice("iPhone")])
        let weekly = VO2Trajectory.weeklyTotal(samples, metric: .activeEnergyBurned, calendar: utc)
        XCTAssertEqual(weekly.count, 12)
        XCTAssertEqual(weekly.values.max()!, 2500, accuracy: 1e-9)   // not 5000
        let contrast = VO2Trajectory.evaluate(samples: samples, age: 45, sex: .male,
                                              now: day(12 * 7), calendar: utc)!.volume!
        XCTAssertEqual(contrast.medianWeekly, 1850, accuracy: 1e-9)  // not 3700
    }

    func testNoContrastWhenActivityIsFlat() {
        let samples = alternatingWeeks(energyHigh: 2000, energyLow: 2000,
                                       vo2High: 42, vo2Low: 39)
        let output = VO2Trajectory.evaluate(samples: samples, age: 45, sex: .male,
                                            now: day(12 * 7), calendar: utc)!
        XCTAssertNil(output.volume)   // every week is at the median, nothing to split
    }

    func testRisingRestingHeartRateBecomesALever() {
        var samples = linearYear(from: 40, to: 40)
        // A baseline needs some spread: with a perfectly flat history the z-score
        // is undefined and nothing can be called a deviation from it.
        samples += (0..<20).map { index in
            HealthMetricSample(type: .restingHeartRate, value: 51 + Double(index % 3),
                               start: day(index), source: .oura)
        }
        samples.append(HealthMetricSample(type: .restingHeartRate, value: 68,
                                          start: day(21), source: .oura))
        let output = VO2Trajectory.evaluate(samples: samples, age: 45, sex: .male,
                                            now: afterAYear, calendar: utc)!
        XCTAssertTrue(output.levers.contains { $0.isPersonal && $0.title.contains("Resting heart rate") })
    }

    func testGeneralEvidenceLeversAreAlwaysOfferedAndLabelled() {
        let output = VO2Trajectory.evaluate(samples: linearYear(from: 40, to: 40),
                                           age: 45, sex: .male, now: afterAYear,
                                           calendar: utc)!
        XCTAssertTrue(output.levers.contains { !$0.isPersonal })
        XCTAssertTrue(output.levers.contains { $0.title.contains("intervals") })
    }
}

final class CardioTrajectoryInsightTests: XCTestCase {

    private func profile(age: Double = 45, male: Bool = true) -> UserHealthProfile {
        var p = UserHealthProfile()
        let now = afterAYear
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-age * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: now))
        return p
    }

    func testNeedsAgeAndSexBeforeItCanJudgeATrend() {
        let result = FitnessInsight().evaluate(
            samples: linearYear(from: 38, to: 40), profile: UserHealthProfile(), now: afterAYear)
        XCTAssertNil(result.primaryValue)
        XCTAssertEqual(result.headline, "Add your details")
        XCTAssertTrue(result.unmetRequirements.contains { $0.kind == .dateOfBirth })
    }

    func testImprovingTrendIsHeadlinedAndScoredAboveMidDial() {
        let result = FitnessInsight().evaluate(
            samples: linearYear(from: 38, to: 40), profile: profile(), now: afterAYear)
        // The card headlines the *level* — "how fit am I" is first a question
        // about where you are — and carries the direction as a line.
        XCTAssertEqual(result.primaryValue!, 40, accuracy: 0.1)   // the VO₂max itself
        XCTAssertEqual(result.confidence, .high)                  // 52 readings over a year
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Improving") })
        XCTAssertTrue(result.drivers.contains { $0.contains("net of ageing") })
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Fitness age") })
    }

    func testHoldingLevelScoresAboveTheAgeTypicalMidpoint() {
        let result = FitnessInsight().evaluate(
            samples: linearYear(from: 40, to: 40), profile: profile(), now: afterAYear)
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Holding") })
        // Holding level beats the age-typical decline, so the trajectory half
        // scores above its 60 midpoint and pulls the composite up.
        let declining = FitnessInsight().evaluate(
            samples: linearYear(from: 42, to: 39), profile: profile(), now: afterAYear)
        XCTAssertGreaterThan(result.score!, declining.score!)
    }

    func testDecliningTrendScoresBelowTheMidpoint() {
        let result = FitnessInsight().evaluate(
            samples: linearYear(from: 42, to: 39), profile: profile(), now: afterAYear)
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Declining") })
        XCTAssertGreaterThanOrEqual(result.score!, 0)
        XCTAssertLessThanOrEqual(result.score!, 100)
    }

    func testNoReadingsSaysSoWithoutPretendingToATrend() {
        let result = FitnessInsight().evaluate(samples: [], profile: profile(),
                                                       now: afterAYear)
        XCTAssertEqual(result.headline, "No readings yet")
        XCTAssertNil(result.score)
        XCTAssertEqual(result.confidence, .low)
    }

    func testTooFewReadingsIsDistinguishedFromNone() {
        let result = FitnessInsight().evaluate(samples: vo2Weekly([40, 41, 42]),
                                                       profile: profile(), now: day(21))
        // Three readings is a level but not a trajectory, and the card says so
        // rather than drawing a line through them.
        XCTAssertNotNil(result.score, "a level does not wait on a trajectory")
        XCTAssertTrue(result.drivers.contains { $0.contains("Not enough readings yet for a trajectory") })
    }

    func testStaleReadingsSayTheyAreStaleRatherThanMissing() {
        let result = FitnessInsight().evaluate(
            samples: linearYear(from: 38, to: 40), profile: profile(),
            now: afterAYear.addingTimeInterval(200 * 86_400))
        XCTAssertTrue(result.drivers.contains { $0.contains("days ago") },
                      "a stale reading must say it is stale rather than read as current")
    }

    func testRegisteredInTheEngineAsATrendInsight() {
        let engine = InsightEngine()
        XCTAssertTrue(engine.models.contains { $0.id == .fitness })
        let result = engine.result(for: .fitness, samples: linearYear(from: 38, to: 40),
                                  profile: profile(), now: afterAYear)!
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Improving") })
        XCTAssertEqual(result.id.cadence, .trend)
    }
}
