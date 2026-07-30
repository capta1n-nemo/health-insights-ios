import XCTest
@testable import InsightKit

/// Three cards were scoring badly or not at all, in three different ways:
/// Cardiovascular Risk mapped a continuous risk onto four fixed numbers, Body
/// Composition passed `score: nil` unconditionally, and Blood Pressure only
/// filled its dial from a reading under 24 hours old.
final class RiskDialTests: XCTestCase {

    /// The defect, stated directly. 4.9 % dialled 90 and 5.1 % dialled 72 — an
    /// 18-point drop across two tenths of a percentage point.
    func testTheDialDoesNotStepAtTheBandEdges() {
        for edge in [5.0, 10.0, 20.0] {
            let below = CardiovascularRiskInsight.score(pct: edge - 0.001)
            let above = CardiovascularRiskInsight.score(pct: edge + 0.001)
            XCTAssertEqual(below, above, accuracy: 0.05,
                           "the dial still steps at the \(edge)% band edge")
        }
    }

    /// The replacement has to agree with the numbers it replaces, or every
    /// user's card moves for no reason they can see.
    func testTheDialAgreesWithTheOldAnchorsAtBandMidpoints() {
        XCTAssertEqual(CardiovascularRiskInsight.score(pct: 2.5), 90, accuracy: 4)
        XCTAssertEqual(CardiovascularRiskInsight.score(pct: 7.5), 72, accuracy: 3)
        XCTAssertEqual(CardiovascularRiskInsight.score(pct: 15),  45, accuracy: 3)
        XCTAssertEqual(CardiovascularRiskInsight.score(pct: 30),  20, accuracy: 3)
    }

    /// Never rises, and stays inside the clamp. Not *strictly* decreasing: the
    /// 1…99 clamp is deliberate — a perfect score and a hopeless one should both
    /// have to be earned — so the tails are flat by design.
    func testTheDialNeverRisesAndStaysBounded() {
        var previous = 100.0
        for tenths in 1...600 {
            let pct = Double(tenths) / 10
            let score = CardiovascularRiskInsight.score(pct: pct)
            XCTAssertLessThanOrEqual(score, previous, "score rose at \(pct)%")
            XCTAssertGreaterThanOrEqual(score, 1)
            XCTAssertLessThanOrEqual(score, 99)
            previous = score
        }
    }

    /// And strictly decreasing everywhere the clamp isn't binding, which is the
    /// whole range a real risk figure lands in.
    func testTheDialIsStrictlyDecreasingAwayFromTheClamp() {
        var previous = CardiovascularRiskInsight.score(pct: 1.0)
        for tenths in 11...500 {
            let pct = Double(tenths) / 10
            let score = CardiovascularRiskInsight.score(pct: pct)
            XCTAssertLessThan(score, previous, "score did not fall at \(pct)%")
            previous = score
        }
    }

    /// The label keeps the clinical thresholds even though the dial no longer
    /// shares them — the copy says "low" / "high" and those words are bands.
    func testBandLabelsKeepTheClinicalThresholds() {
        let insight = CardiovascularRiskInsight()
        XCTAssertEqual(insight.riskBand(pct: 4.9).label, "low")
        XCTAssertEqual(insight.riskBand(pct: 5.1).label, "low-to-moderate")
        XCTAssertEqual(insight.riskBand(pct: 19.9).label, "moderate-to-high")
        XCTAssertEqual(insight.riskBand(pct: 20.1).label, "high")
    }
}

final class CholesterolFreshnessTests: XCTestCase {

    private func fullProfile(cholesterolRecordedAt: Date? = nil) -> UserHealthProfile {
        let now = Date()
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-55 * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        p.set(.init(kind: .cuffSystolic, value: 130, recordedAt: now))
        p.set(.init(kind: .cuffDiastolic, value: 82, recordedAt: now))
        let recorded = cholesterolRecordedAt ?? now
        p.set(.init(kind: .totalCholesterol, value: 5.5, recordedAt: recorded))
        p.set(.init(kind: .hdlCholesterol, value: 1.3, recordedAt: recorded))
        return p
    }

    func testCholesterolGoesStaleAtSixMonths() {
        let now = Date()
        XCTAssertFalse(GroundingInput(kind: .totalCholesterol, value: 5.5,
                                      recordedAt: now.addingTimeInterval(-200 * 86_400))
            .isFresh(asOf: now))
        XCTAssertTrue(GroundingInput(kind: .totalCholesterol, value: 5.5,
                                     recordedAt: now.addingTimeInterval(-170 * 86_400))
            .isFresh(asOf: now))
    }

    /// An aged lab is still the best number available — better than a population
    /// average — so the arithmetic must not change. What it stops buying is a
    /// silent pass at high confidence.
    func testAnAgedCholesterolIsStillUsedButNoLongerHighConfidence() {
        let now = Date()
        let insight = CardiovascularRiskInsight(preferredEngine: .combined)
        let aged = insight.evaluate(
            samples: [],
            profile: fullProfile(cholesterolRecordedAt: now.addingTimeInterval(-200 * 86_400)),
            now: now)
        let fresh = insight.evaluate(samples: [], profile: fullProfile(), now: now)

        XCTAssertEqual(try XCTUnwrap(aged.primaryValue), try XCTUnwrap(fresh.primaryValue),
                       accuracy: 1e-9, "a stale lab must not change the arithmetic")
        XCTAssertEqual(fresh.confidence, .high)
        XCTAssertEqual(aged.confidence, .moderate)
        XCTAssertFalse(aged.drivers.contains { $0.lowercased().contains("assumed average") },
                       "the lab is present — it must not be reported as assumed")
        XCTAssertTrue(aged.drivers.contains { $0.contains("over six months old") })
    }
}

final class BodyCompositionDialTests: XCTestCase {

    private func sample(_ type: MetricType, _ value: Double, daysAgo: Int) -> HealthMetricSample {
        HealthMetricSample(type: type, value: value,
                           start: Date().addingTimeInterval(-Double(daysAgo) * 86_400),
                           source: .withings)
    }

    private func profile(age: Double, male: Bool) -> UserHealthProfile {
        var p = UserHealthProfile()
        let now = Date()
        p.set(.init(kind: .dateOfBirth,
                    value: now.addingTimeInterval(-age * 365.2425 * 86_400).timeIntervalSince1970,
                    recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: now))
        return p
    }

    func testScoresBodyFatAgainstTheAgeAndSexRange() {
        let samples = [sample(.bodyMass, 80, daysAgo: 0), sample(.height, 1.80, daysAgo: 100),
                       sample(.bodyFatPercentage, 13.5, daysAgo: 0)]
        let result = BodyCompositionInsight()
            .evaluate(samples: samples, profile: profile(age: 35, male: true), now: Date())
        XCTAssertEqual(try XCTUnwrap(result.score), 100, accuracy: 0.5)  // centre of 8–19 %
        XCTAssertEqual(result.confidence, .high)
    }

    func testFallsBackToBMIAtLowerConfidence() {
        let samples = [sample(.bodyMass, 80, daysAgo: 0), sample(.height, 1.80, daysAgo: 100)]
        let result = BodyCompositionInsight().evaluate(samples: samples, profile: .init(), now: Date())
        XCTAssertEqual(try XCTUnwrap(result.score), 84.3, accuracy: 1)   // BMI 24.69 vs 18.5–24.9
        XCTAssertEqual(result.confidence, .moderate)
        XCTAssertTrue(result.unmetRequirements.contains { $0.kind == .dateOfBirth })
    }

    /// The whole reason body fat leads: BMI cannot tell muscle from fat, and
    /// this card exists to draw exactly that distinction.
    func testBodyFatOutvotesBMIWhenBothArePresent() {
        // A muscular 35-year-old. BMI 27.8 says "overweight"; 12 % body fat does not.
        let samples = [sample(.bodyMass, 90, daysAgo: 0), sample(.height, 1.80, daysAgo: 100),
                       sample(.bodyFatPercentage, 12, daysAgo: 0)]
        let result = BodyCompositionInsight()
            .evaluate(samples: samples, profile: profile(age: 35, male: true), now: Date())
        XCTAssertGreaterThan(try XCTUnwrap(result.score), 90,
                             "BMI must not out-vote a measured fat fraction")
    }

    func testScoresNilWithNeitherHeightNorBodyFat() {
        let result = BodyCompositionInsight()
            .evaluate(samples: [sample(.bodyMass, 80, daysAgo: 0)], profile: .init(), now: Date())
        XCTAssertNil(result.score)
    }

    func testTooMuchFatCostsMoreThanTooLittle() {
        XCTAssertEqual(BodyCompositionInsight.rangeScore(19, lower: 8, upper: 19), 82.3, accuracy: 0.5)
        XCTAssertLessThan(BodyCompositionInsight.rangeScore(30, lower: 8, upper: 19),
                          BodyCompositionInsight.rangeScore(6, lower: 8, upper: 19))
    }
}

final class BloodPressureTrendDialTests: XCTestCase {

    private func reading(_ sys: Double, _ dia: Double, daysAgo: Double) -> [HealthMetricSample] {
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        return [
            HealthMetricSample(type: .bloodPressureSystolic, value: sys, start: date,
                               source: .appleHealthDevice("Cuff")),
            HealthMetricSample(type: .bloodPressureDiastolic, value: dia, start: date,
                               source: .appleHealthDevice("Cuff"))
        ]
    }

    /// The defect: someone who cuffs weekly saw an empty dial six days in seven.
    func testAWeeklyCufferStillGetsADial() {
        var samples: [HealthMetricSample] = []
        for d in [3.0, 10, 17, 24] { samples += reading(122, 80, daysAgo: d) }
        let result = BloodPressureInsight().evaluate(samples: samples, profile: .init(), now: Date())
        XCTAssertNotNil(result.score, "no reading today means no dial, which is the bug")
        XCTAssertEqual(result.confidence, .moderate)
        XCTAssertTrue(result.drivers.contains { $0.contains("Recent average") })
    }

    /// One reading is a moment, not a pattern, and averaging it would be the old
    /// behaviour wearing a new word.
    func testOneAgedReadingIsNotAPattern() {
        let result = BloodPressureInsight()
            .evaluate(samples: reading(122, 80, daysAgo: 9), profile: .init(), now: Date())
        XCTAssertNil(result.score)
    }

    /// A reading from today is today's answer and outranks the average.
    func testAFreshReadingStillWins() {
        var samples = reading(118, 76, daysAgo: 0)
        for d in [8.0, 15, 22] { samples += reading(150, 95, daysAgo: d) }
        let result = BloodPressureInsight().evaluate(samples: samples, profile: .init(), now: Date())
        XCTAssertEqual(try XCTUnwrap(result.score),
                       BloodPressureEstimator.score(systolic: 118, diastolic: 76), accuracy: 1e-9)
    }

    func testTheTrendReportsDriftPerWeekNotPerReading() {
        var samples: [HealthMetricSample] = []
        // Exactly 2 mmHg a week, sampled irregularly. Fitted against elapsed
        // time this is 2.0; fitted against reading *index* — four points, evenly
        // spaced by position — it would come out at 2.67, which is a number
        // about the sampling rather than about the person.
        for (days, sys) in [(28.0, 118.0), (21, 120), (14, 122), (0, 126)] {
            samples += reading(sys, 80, daysAgo: days)
        }
        let trend = try? XCTUnwrap(BloodPressureEstimator.recentTrend(from: samples))
        XCTAssertEqual(try XCTUnwrap(trend?.systolicPerWeek), 2, accuracy: 0.3)
        XCTAssertEqual(trend?.readingCount, 4)
    }
}

final class BloodPressureCalibrationPhaseTests: XCTestCase {

    private func reading(_ sys: Double, _ dia: Double, daysAgo: Double) -> [HealthMetricSample] {
        let date = Date().addingTimeInterval(-daysAgo * 86_400)
        return [
            HealthMetricSample(type: .bloodPressureSystolic, value: sys, start: date,
                               source: .appleHealthDevice("Cuff")),
            HealthMetricSample(type: .bloodPressureDiastolic, value: dia, start: date,
                               source: .appleHealthDevice("Cuff"))
        ]
    }

    /// `maintenanceReadingsPerMonth = 2` was declared and never read, so the app
    /// demanded five readings every thirty days forever.
    func testMaintenanceAsksForTwoAMonthOnceTheInitialFiveAreDone() {
        var samples: [HealthMetricSample] = []
        for d in [62.0, 68, 74, 80, 86] { samples += reading(120, 80, daysAgo: d) }
        for d in [3.0, 19] { samples += reading(122, 81, daysAgo: d) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.phase, .maintenance)
        XCTAssertEqual(status.required, 2)
        XCTAssertTrue(status.isGrounded)
    }

    func testAMaintenanceLapseAsksForOneMoreNotFive() {
        var samples: [HealthMetricSample] = []
        for d in [62.0, 68, 74, 80, 86] { samples += reading(120, 80, daysAgo: d) }
        samples += reading(122, 81, daysAgo: 9)
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertEqual(status.phase, .maintenance)
        XCTAssertFalse(status.isGrounded)
        XCTAssertEqual(status.neededForGrounding, 1)
    }

    /// Calibrated a year ago and nothing since: the regression cannot be
    /// refitted, so the full initial ask is the honest one.
    func testAFitWindowThatHasEmptiedOutDemandsTheFullFiveAgain() {
        var samples: [HealthMetricSample] = []
        for d in [360.0, 366, 372, 378, 384] { samples += reading(120, 80, daysAgo: d) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertTrue(status.hasCompletedInitial)
        XCTAssertEqual(status.phase, .expired)
        XCTAssertEqual(status.required, 5)
    }

    /// Five readings spread 35 days apart never form a calibration, however many
    /// of them there are.
    func testFiveReadingsSpreadTooThinNeverCompleteTheInitial() {
        var samples: [HealthMetricSample] = []
        for d in [5.0, 40, 75, 110, 145] { samples += reading(120, 80, daysAgo: d) }
        let status = BloodPressureEstimator.calibrationStatus(from: samples)
        XCTAssertFalse(status.hasCompletedInitial)
        XCTAssertEqual(status.phase, .initial)
        XCTAssertEqual(status.required, 5)
    }
}
