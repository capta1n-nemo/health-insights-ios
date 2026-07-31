import XCTest
@testable import InsightKit

// MARK: - Fitness age

final class FitnessAgeTests: XCTestCase {

    func testReferenceMatchesTheNormTableAnchors() {
        // The continuous line must pass exactly through the band midpoints the
        // scoring table uses, or the two would disagree about "average for age".
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 25, sex: .male), 48, accuracy: 1e-9)
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 45, sex: .male), 40, accuracy: 1e-9)
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 65, sex: .male), 32, accuracy: 1e-9)
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 25, sex: .female), 41, accuracy: 1e-9)
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 55, sex: .female), 31, accuracy: 1e-9)
    }

    func testReferenceInterpolatesAndExtrapolatesTheEndSlopes() {
        // Midway between two anchors.
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 30, sex: .male), 46, accuracy: 1e-9)
        // Below the first anchor: continue the adjacent slope (−0.4/yr for males).
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 20, sex: .male), 50, accuracy: 1e-9)
        // Above the last: continue the final slope (−0.3/yr for females).
        XCTAssertEqual(FitnessAgeModel.referenceVO2(age: 75, sex: .female), 25, accuracy: 1e-9)
    }

    func testReferenceIsStrictlyDecreasingAcrossTheReportableBand() {
        // Inversion by bisection is only valid because of this.
        for sex in BiologicalSex.allCases {
            var previous = Double.greatestFiniteMagnitude
            var age = FitnessAgeModel.youngestReportable
            while age <= FitnessAgeModel.oldestReportable {
                let value = FitnessAgeModel.referenceVO2(age: age, sex: sex)
                XCTAssertLessThan(value, previous, "not decreasing at age \(age) for \(sex)")
                previous = value
                age += 0.5
            }
        }
    }

    func testFitnessAgeInvertsTheReferenceLine() {
        // Feeding in the reference VO₂max for an age must return that same age.
        for age in [24.0, 33.0, 42.0, 58.0, 70.0] {
            let vo2 = FitnessAgeModel.referenceVO2(age: age, sex: .male)
            let out = FitnessAgeModel.evaluate(vo2: vo2, sex: .male)
            XCTAssertEqual(out.fitnessAge, age, accuracy: 0.01)
            XCTAssertFalse(out.isCapped)
        }
    }

    func testFitterThanYourYearsReportsYearsInHand() {
        // A 50-year-old male with the reference VO₂max of a 35-year-old.
        let out = FitnessAgeModel.evaluate(vo2: 44, sex: .male, chronologicalAge: 50)
        XCTAssertEqual(out.fitnessAge, 35, accuracy: 0.01)
        XCTAssertEqual(out.yearsYounger!, 15, accuracy: 0.01)
        XCTAssertEqual(out.referenceForOwnAge!, 38, accuracy: 1e-9)   // norm at 50
    }

    func testOutOfBandVO2IsClampedAndFlagged() {
        let elite = FitnessAgeModel.evaluate(vo2: 70, sex: .male)
        XCTAssertEqual(elite.fitnessAge, FitnessAgeModel.youngestReportable)
        XCTAssertTrue(elite.isCapped)

        let low = FitnessAgeModel.evaluate(vo2: 15, sex: .female)
        XCTAssertEqual(low.fitnessAge, FitnessAgeModel.oldestReportable)
        XCTAssertTrue(low.isCapped)
    }
}

// MARK: - Heart age (vascular age)

final class HeartAgeModelTests: XCTestCase {

    private func subject(systolic: Double = 120, totalChol: Double = 4.65,
                         hdl: Double = 1.55, smoker: Bool = false,
                         diabetes: Bool = false, treated: Bool = false,
                         sex: BiologicalSex = .male) -> HeartAgeModel.Subject {
        HeartAgeModel.Subject(sex: sex, race: .whiteOrOther, region: .low,
                              systolicBP: systolic, totalCholesterolMmol: totalChol,
                              hdlCholesterolMmol: hdl, isSmoker: smoker,
                              hasDiabetes: diabetes, treatedForBP: treated)
    }

    func testOptimalFactorsGiveBackYourRealAge() {
        // The defining property of the vascular-age method: if your risk factors
        // *are* the optimal reference set, your heart age is your age.
        for age in [42.0, 55.0, 62.0] {
            for engine in HeartAgeModel.Engine.allCases where engine.validatedAgeRange.contains(age) {
                let reading = HeartAgeModel.reading(engine, subject: subject(), age: age)
                XCTAssertEqual(reading.heartAge, age, accuracy: 0.3,
                               "\(engine.rawValue) at \(age)")
                XCTAssertEqual(reading.excessYears, 0, accuracy: 0.3)
                XCTAssertFalse(reading.isCapped)
            }
        }
    }

    func testWithOptimalFactorsOnlyTouchesModifiableOnes() {
        let optimal = subject(systolic: 165, totalChol: 7.2, hdl: 0.9, smoker: true,
                              diabetes: true, treated: true, sex: .female).withOptimalFactors
        XCTAssertEqual(optimal.systolicBP, HeartAgeModel.OptimalReference.systolicBP)
        XCTAssertEqual(optimal.totalCholesterolMmol, HeartAgeModel.OptimalReference.totalCholesterolMmol)
        XCTAssertEqual(optimal.hdlCholesterolMmol, HeartAgeModel.OptimalReference.hdlCholesterolMmol)
        XCTAssertFalse(optimal.isSmoker)
        XCTAssertFalse(optimal.hasDiabetes)
        XCTAssertFalse(optimal.treatedForBP)
        // Not modifiable, and swapping them would compare against a different person.
        XCTAssertEqual(optimal.sex, .female)
        XCTAssertEqual(optimal.race, .whiteOrOther)
        XCTAssertEqual(optimal.region, .low)
    }

    func testWorseFactorsAgeTheHeart() {
        let age = 52.0
        let clean = HeartAgeModel.evaluate(subject: subject(), age: age)!
        let smoker = HeartAgeModel.evaluate(subject: subject(smoker: true), age: age)!
        let hypertensive = HeartAgeModel.evaluate(subject: subject(systolic: 160), age: age)!
        let both = HeartAgeModel.evaluate(subject: subject(systolic: 160, smoker: true), age: age)!

        XCTAssertGreaterThan(smoker.heartAge!, clean.heartAge!)
        XCTAssertGreaterThan(hypertensive.heartAge!, clean.heartAge!)
        XCTAssertGreaterThan(both.heartAge!, smoker.heartAge!)
        XCTAssertGreaterThan(both.excessYears!, 0)
    }

    func testRiskAboveTheOldestReferenceIsCappedNotExtrapolated() {
        // Very high risk at a young age: the honest answer is "at least the top of
        // the band", not a number produced by running an equation somewhere it was
        // never validated. Each engine caps at its own ceiling — 69 for SCORE2,
        // 79 for ASCVD — never at the other's.
        let extreme = subject(systolic: 200, totalChol: 9, hdl: 0.6,
                              smoker: true, diabetes: true)
        let out = HeartAgeModel.evaluate(subject: extreme, age: 45)!
        XCTAssertTrue(out.isCapped)
        for reading in out.readings where reading.isCapped {
            XCTAssertEqual(reading.heartAge, reading.engine.validatedAgeRange.upperBound)
        }
        XCTAssertEqual(out.highestHeartAge!,
                       HeartAgeModel.Engine.ascvd.validatedAgeRange.upperBound)
    }

    func testHeartAgeNeverLeavesTheEnginesValidatedBand() {
        // Sweep a wide spread of factor sets: no reading may fall outside the
        // engine's own range, in either direction.
        for systolic in [100.0, 130.0, 175.0] {
            for smoker in [false, true] {
                for age in [41.0, 55.0, 68.0, 78.0] {
                    guard let out = HeartAgeModel.evaluate(
                        subject: subject(systolic: systolic, smoker: smoker), age: age) else { continue }
                    for reading in out.readings {
                        XCTAssertTrue(reading.engine.validatedAgeRange.contains(reading.heartAge),
                                      "\(reading.engine.rawValue) returned \(reading.heartAge)")
                    }
                }
            }
        }
    }

    func testOnlyEnginesValidatedAtThisAgeContribute() {
        // 40–69: both. 70–79: ASCVD alone. Outside 40–79: no heart age at all.
        XCTAssertEqual(HeartAgeModel.evaluate(subject: subject(), age: 55)!.readings.count, 2)
        let seventies = HeartAgeModel.evaluate(subject: subject(), age: 74)!
        XCTAssertEqual(seventies.readings.count, 1)
        XCTAssertEqual(seventies.readings.first!.engine, .ascvd)
        XCTAssertNil(HeartAgeModel.evaluate(subject: subject(), age: 32))
        XCTAssertNil(HeartAgeModel.evaluate(subject: subject(), age: 85))
    }

    func testConsensusIsTheMeanOfTheEngines() {
        let out = HeartAgeModel.evaluate(subject: subject(systolic: 145, smoker: true), age: 58)!
        let mean = out.readings.map(\.heartAge).reduce(0, +) / Double(out.readings.count)
        XCTAssertEqual(out.heartAge!, mean, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(out.lowestHeartAge!, out.heartAge!)
        XCTAssertGreaterThanOrEqual(out.highestHeartAge!, out.heartAge!)
    }

    func testOptimalRiskIsLowerThanYourOwnWhenFactorsAreWorse() {
        let reading = HeartAgeModel.reading(.ascvd, subject: subject(systolic: 155, smoker: true),
                                           age: 60)
        XCTAssertGreaterThan(reading.riskPercent, reading.optimalRiskPercent)
    }

    func testProjectionOnlyUsesValidatedAgesAndLooksAhead() {
        let projections = HeartAgeModel.projection(subject: subject(systolic: 135),
                                                  currentAge: 46)
        XCTAssertEqual(projections.map(\.age), [60, 70, 79])   // 50 is inside +5 years
        // SCORE2 stops at 69, so the later points are ASCVD only.
        XCTAssertEqual(projections.first!.engines, [.score2, .ascvd])
        XCTAssertEqual(projections.last!.engines, [.ascvd])
        // Risk with fixed factors rises with age.
        for (earlier, later) in zip(projections, projections.dropFirst()) {
            XCTAssertGreaterThan(later.percent, earlier.percent)
        }
    }

    func testProjectionIsEmptyPastTheValidatedBand() {
        XCTAssertTrue(HeartAgeModel.projection(subject: subject(), currentAge: 76).isEmpty)
    }
}

// MARK: - The insight surface

final class HeartAgeAnalyserTests: XCTestCase {
    private let now = Date()

    private func profile(age: Double, male: Bool = true, systolic: Double? = nil,
                         cholesterol: Bool = false) -> UserHealthProfile {
        var p = UserHealthProfile()
        let dob = now.addingTimeInterval(-age * 365.2425 * 86_400)
        p.set(.init(kind: .dateOfBirth, value: dob.timeIntervalSince1970, recordedAt: now))
        p.set(.init(kind: .biologicalSex, value: male ? 0 : 1, recordedAt: now))
        if let systolic {
            p.set(.init(kind: .cuffSystolic, value: systolic, recordedAt: now))
        }
        if cholesterol {
            p.set(.init(kind: .totalCholesterol, value: 5.4, recordedAt: now))
            p.set(.init(kind: .hdlCholesterol, value: 1.2, recordedAt: now))
        }
        return p
    }

    private func vo2(_ value: Double) -> [HealthMetricSample] {
        [HealthMetricSample(type: .vo2Max, value: value, start: now, source: .appleHealth)]
    }

    func testFitnessAgeAloneWorksWithNoGroundingBeyondAgeAndSex() {
        // The half that needs nothing from the user must still land: an Apple
        // Watch supplies VO₂max unprompted.
        let insight = HeartAgeAnalyser()
        let analysis = insight.analyse(samples: vo2(44), profile: profile(age: 50), now: now)
        XCTAssertNil(analysis.heart)
        XCTAssertEqual(analysis.fitness!.fitnessAge, 35, accuracy: 0.01)

        // And it reaches the user on the Fitness card, which asks for nothing
        // the risk equations need.
        let result = FitnessInsight().evaluate(samples: vo2(44), profile: profile(age: 50),
                                               now: now)
        XCTAssertEqual(result.primaryValue!, 44, accuracy: 0.01)   // the VO₂max itself
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Fitness age 35") },
                      result.drivers.joined(separator: " | "))
    }

    // MARK: - Where the card's two halves went
    //
    // Heart & Fitness Age is no longer a card. `HeartAgeAnalyser` still computes
    // both ages and every test above still exercises it directly — what changed
    // is who *renders* them: the heart age moved to Heart Attack & Stroke Risk,
    // which already runs the same SCORE2/ASCVD equations this inverts, and the
    // fitness age moved to Fitness.

    func testBloodPressureUnlocksHeartAge() {
        let p = profile(age: 55, systolic: 150)
        let analysis = HeartAgeAnalyser().analyse(samples: vo2(38), profile: p, now: now)
        XCTAssertNotNil(analysis.heart)
        XCTAssertTrue(analysis.assumedCholesterol)
        XCTAssertGreaterThan(analysis.heart!.heartAge!, 55)   // 150 mmHg is not optimal
    }

    /// The heart age reaches the user, on the risk card.
    func testHeartAgeIsReportedByTheRiskCard() {
        let result = CardiovascularRiskInsight(preferredEngine: .combined)
            .evaluate(samples: vo2(38), profile: profile(age: 55, systolic: 150), now: now)
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Heart age") },
                      "heart age should be a line on the risk card")
        XCTAssertTrue(result.drivers.contains { $0.contains("modifiable part") })
    }

    /// And says where its other half went, because the two can disagree and the
    /// card that used to show them side by side is gone.
    func testTheRiskCardPointsAtFitnessAgeRatherThanLeavingItUnexplained() {
        let result = CardiovascularRiskInsight(preferredEngine: .combined)
            .evaluate(samples: vo2(38), profile: profile(age: 55, systolic: 150), now: now)
        XCTAssertTrue(result.drivers.contains { $0.contains("Fitness card") })
    }

    /// The fitness age reaches the user, on the Fitness card — and needs no
    /// blood pressure to do it, which was the whole reason the two halves were
    /// worth separating.
    func testFitnessAgeIsReportedByTheFitnessCardWithoutAnyClinicalGrounding() {
        let result = FitnessInsight().evaluate(samples: vo2(42),
                                               profile: profile(age: 50), now: now)
        XCTAssertTrue(result.drivers.contains { $0.hasPrefix("Fitness age") })
        XCTAssertNotNil(result.score)
    }

    func testNothingToSayWithoutAgeOrSex() {
        let result = FitnessInsight().evaluate(samples: vo2(44), profile: UserHealthProfile(),
                                               now: now)
        XCTAssertNil(result.primaryValue)
        XCTAssertEqual(result.headline, "Add your details")
        XCTAssertTrue(result.unmetRequirements.contains { $0.kind == .dateOfBirth })
    }

    /// Under 40 both risk equations are extrapolation, so the clinical half is
    /// withheld rather than guessed at — while the sensed half still shows.
    /// That asymmetry is why the split works.
    func testYoungUserGetsFitnessAgeButNoHeartAge() {
        let p = profile(age: 32, systolic: 150)
        let analysis = HeartAgeAnalyser().analyse(samples: vo2(42), profile: p, now: now)
        XCTAssertNil(analysis.heart)
        XCTAssertNotNil(analysis.fitness)
        XCTAssertFalse(analysis.projections.isEmpty)

        let fitness = FitnessInsight().evaluate(samples: vo2(42), profile: p, now: now)
        XCTAssertNotNil(fitness.score, "fitness does not wait on the risk equations")
    }

    func testExcessPhrasingReadsAsEnglish() {
        XCTAssertEqual(HeartAgeAnalyser.excessPhrase(0.4), "about the same as your real age")
        XCTAssertEqual(HeartAgeAnalyser.excessPhrase(1.2), "1 year older than you are")
        XCTAssertEqual(HeartAgeAnalyser.excessPhrase(-6), "6 years younger than you are")
    }

    func testCappedAgesAreSaidOutLoudRatherThanShownAsFact() {
        XCTAssertEqual(HeartAgeAnalyser.heartAgePhrase(79, capped: true), "79 or older")
        XCTAssertEqual(HeartAgeAnalyser.heartAgePhrase(40, capped: true), "40 or younger")
        XCTAssertEqual(HeartAgeAnalyser.fitnessAgePhrase(20, capped: true), "20 or younger")
        XCTAssertEqual(HeartAgeAnalyser.fitnessAgePhrase(75, capped: true), "75 or older")
        XCTAssertEqual(HeartAgeAnalyser.fitnessAgePhrase(52.4, capped: false), "52")
    }

    /// The card is gone; both of its halves are registered and reachable.
    func testBothHalvesAreRegisteredInTheEngine() {
        let engine = InsightEngine()
        XCTAssertFalse(engine.models.contains { $0.id.rawValue == "heartAge" },
                       "Heart & Fitness Age was merged and should not be registered")
        for id in [InsightID.fitness, .cardiovascularRisk] {
            XCTAssertTrue(engine.models.contains { $0.id == id }, "\(id) missing")
            let result = engine.result(for: id, samples: vo2(44),
                                       profile: profile(age: 50), now: now)
            XCTAssertNotNil(result)
            XCTAssertEqual(result!.id.cadence, .trend)
        }
    }
}
