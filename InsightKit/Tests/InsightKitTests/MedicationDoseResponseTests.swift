import XCTest
@testable import InsightKit

/// **What the drug is doing** — backlog `R24` (intake versus expenditure) and
/// `B3-21` (everything folded onto days-since-dose).
///
/// Half of this file is about a claim being *refused*. "Mounjaro speeds up your
/// metabolism" is not established, a rising intake/expenditure ratio during
/// treatment is more likely a food log that got worse as appetite fell, and
/// Apple's basal energy is a formula evaluated from height, weight, age and sex
/// rather than a measurement of anybody's metabolism. So there are tests here
/// asserting that certain words never appear and that certain numbers are never
/// combined.
final class MedicationDoseResponseTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// Fourteen weekly tirzepatide doses — the reader's real regimen.
    private func doses(count: Int = 14, everyDays: Double = 7) -> [AdministeredDose] {
        (0..<count).map {
            AdministeredDose(takenAt: now.addingTimeInterval(-Double(count - $0) * everyDays * 86_400),
                             milligrams: 5)
        }
    }

    /// One reading a day, `beforeValue` before `boundary` and `afterValue` after,
    /// with a ±1 sawtooth so the before-period has a real spread.
    private func daily(_ metric: MetricType, before: Double, after: Double,
                       boundary: Date, days: Int = 200) -> [HealthMetricSample] {
        (0...days).compactMap { day in
            let at = now.addingTimeInterval(-Double(day) * 86_400)
            guard at <= now else { return nil }
            let jitter = Double(day % 3) - 1
            return HealthMetricSample(type: metric,
                                      value: (at < boundary ? before : after) + jitter,
                                      start: at, source: .appleHealth)
        }
    }

    private var firstDose: Date { doses().map(\.takenAt).min()! }

    // MARK: - R24: intake and expenditure, separately

    func testIntakeFallingWhileExpenditureHoldsIsTheEatNotBurnSentence() throws {
        let samples = daily(.dietaryEnergy, before: 2400, after: 1700, boundary: firstDose)
            + daily(.activeEnergyBurned, before: 500, after: 500, boundary: firstDose)
        let contrast = try XCTUnwrap(MedicationDoseResponse.contrast(
            doses: doses(), samples: samples, now: now, calendar: utc))
        XCTAssertTrue(contrast.sentence.contains("moved what you eat, not what you burn"),
                      "got: \(contrast.sentence)")
        XCTAssertEqual(contrast.intake?.moved, true)
        XCTAssertEqual(contrast.expenditure?.moved, false)
    }

    func testTheTwoDeltasAreReportedSeparatelyAndNeverCombined() throws {
        let samples = daily(.dietaryEnergy, before: 2400, after: 1700, boundary: firstDose)
            + daily(.activeEnergyBurned, before: 500, after: 700, boundary: firstDose)
        let contrast = try XCTUnwrap(MedicationDoseResponse.contrast(
            doses: doses(), samples: samples, now: now, calendar: utc))
        XCTAssertEqual(contrast.rows.count, 2)
        XCTAssertTrue(contrast.sentence.contains("reported separately"),
                      "both moving must say why there is no single number: \(contrast.sentence)")
        let mirror = Mirror(reflecting: contrast)
        for child in mirror.children {
            let label = (child.label ?? "").lowercased()
            XCTAssertFalse(label.contains("ratio") || label.contains("net"),
                           "a combined intake/expenditure figure is a metabolism claim")
        }
    }

    /// The named trap. No arm of the sentence machine may produce it, on any
    /// combination of the two deltas.
    func testNoArmOfTheSentenceEverClaimsTheDrugChangedYourMetabolism() {
        let banned = ["speeds up", "speed up", "faster metabolism", "boosts your metabolism",
                      "raises your metabolism", "your metabolism is"]
        let values: [Double?] = [nil, -800, -50, 50, 800]
        for i in values {
            for e in values {
                let intake = i.map {
                    MedicationDoseResponse.BeforeAfter(
                        metric: .dietaryEnergy, label: "What you ate", isSelfReported: true,
                        beforeMean: 2400, afterMean: 2400 + $0, beforeSD: 200,
                        beforeDays: 40, afterDays: 40)
                }
                let expenditure = e.map {
                    MedicationDoseResponse.BeforeAfter(
                        metric: .activeEnergyBurned, label: "What you burned moving",
                        isSelfReported: false, beforeMean: 500, afterMean: 500 + $0,
                        beforeSD: 150, beforeDays: 40, afterDays: 40)
                }
                let sentence = MedicationDoseResponse
                    .sentence(intake: intake, expenditure: expenditure).lowercased()
                for phrase in banned {
                    XCTAssertFalse(sentence.contains(phrase),
                                   "'\(phrase)' reached the card: \(sentence)")
                }
            }
        }
    }

    /// Standing copy, checked rather than trusted: the section has to say out
    /// loud that neither series is a metabolism, and that intake is self-reported.
    func testTheStandingRefusalsSayWhatTheyMustSay() {
        XCTAssertTrue(MedicationDoseResponse.notMetabolism.contains("measurement of your metabolism"))
        XCTAssertTrue(MedicationDoseResponse.notMetabolism.contains("GLP-1"))
        XCTAssertTrue(MedicationDoseResponse.intakeIsSelfReported.contains("logged"))
    }

    /// **Apple's basal energy is never a subject here.** There is no basal term
    /// in the module, and this is the test that keeps it that way — the trap is
    /// that somebody adds one because it looks like the metabolism number the
    /// reader asked for.
    func testNoBasalOrRestingEnergySeriesIsReadAtAll() {
        let intake = MedicationDoseResponse.BeforeAfter(
            metric: .dietaryEnergy, label: "What you ate", isSelfReported: true,
            beforeMean: 2400, afterMean: 1800, beforeSD: 200, beforeDays: 40, afterDays: 40)
        XCTAssertEqual(intake.metric, .dietaryEnergy)
        let expenditure = MedicationDoseResponse.BeforeAfter(
            metric: .activeEnergyBurned, label: "What you burned moving", isSelfReported: false,
            beforeMean: 500, afterMean: 520, beforeSD: 150, beforeDays: 40, afterDays: 40)
        XCTAssertEqual(expenditure.metric, .activeEnergyBurned,
                       "expenditure is what the watch measured moving, never a formula")
        XCTAssertFalse(expenditure.isSelfReported)
        XCTAssertTrue(intake.isSelfReported)
    }

    func testAThinSideMeansNoContrastRatherThanAConfidentOne() throws {
        // Three days of food logging before the first dose. Below the floor.
        let sparse = (0..<3).map {
            HealthMetricSample(type: .dietaryEnergy, value: 2400,
                               start: firstDose.addingTimeInterval(-Double($0 + 1) * 86_400),
                               source: .manual)
        } + daily(.dietaryEnergy, before: 2400, after: 1700, boundary: firstDose, days: 0)
        let contrast = try XCTUnwrap(MedicationDoseResponse.contrast(
            doses: doses(), samples: sparse, now: now, calendar: utc))
        XCTAssertNil(contrast.intake, "seven days each side is the floor and three is not it")
    }

    func testEnergyIsSummedPerDayRatherThanAveragedOverMeals() {
        let day = utc.startOfDay(for: now)
        let meals = (0..<3).map {
            HealthMetricSample(type: .dietaryEnergy, value: 700,
                               start: day.addingTimeInterval(Double($0) * 3 * 3600),
                               source: .manual)
        }
        XCTAssertEqual(MedicationDoseResponse.dailyTotals(meals, calendar: utc), [2100],
                       "a mean over samples would report the size of a typical meal")
    }

    // MARK: - B3-21: folded onto days since dose

    func testTheCycleComesFromTheReadersOwnDoseSpacing() {
        XCTAssertEqual(MedicationDoseResponse.cycleDays(doses: doses(everyDays: 7)), 7)
        XCTAssertEqual(MedicationDoseResponse.cycleDays(doses: doses(everyDays: 14)), 14)
        XCTAssertNil(MedicationDoseResponse.cycleDays(doses: [doses().first!]),
                     "one dose is not a cycle")
    }

    func testEveryBinCarriesHowManyDosesItRestsOn() throws {
        let regimen = doses()
        let samples = daily(.bodyMass, before: 100, after: 95,
                            boundary: regimen.first!.takenAt)
        let folds = MedicationDoseResponse.folds(doses: regimen, samples: samples,
                                                 metrics: [.bodyMass], now: now, calendar: utc)
        let fold = try XCTUnwrap(folds.first)
        XCTAssertEqual(fold.bins.count, 7, "a weekly cycle has seven day-offsets")
        for bin in fold.bins {
            XCTAssertGreaterThan(bin.doses, 0)
            XCTAssertLessThanOrEqual(bin.doses, regimen.count)
        }
        XCTAssertGreaterThan(fold.weakestBinDoses, 0,
                             "the thinnest bin is what the shape is only as good as")
    }

    /// A dose day the reader happened to wear the watch all day must not outvote
    /// the other thirteen doses at the same offset.
    func testABinIsAMeanOfDosesRatherThanAMeanOfReadings() throws {
        let regimen = doses(count: 3, everyDays: 7)
        var samples: [HealthMetricSample] = []
        for (index, dose) in regimen.enumerated() {
            // Offset 0 and offset 1 both present, so the fold has a shape.
            let value = index == 0 ? 100.0 : 60.0
            let readings = index == 0 ? 50 : 1
            for r in 0..<readings {
                samples.append(HealthMetricSample(
                    type: .heartRate, value: value,
                    start: dose.takenAt.addingTimeInterval(Double(r) * 60), source: .appleHealth))
            }
            samples.append(HealthMetricSample(
                type: .heartRate, value: 60,
                start: dose.takenAt.addingTimeInterval(30 * 3600), source: .appleHealth))
        }
        let fold = try XCTUnwrap(MedicationDoseResponse.folds(
            doses: regimen, samples: samples, metrics: [.heartRate],
            now: now, calendar: utc).first)
        let dayZero = try XCTUnwrap(fold.bins.first { $0.offset == 0 })
        // Three doses at offset 0: 100, 60, 60 → 73.3. Pooled by reading it
        // would be (50×100 + 2×60)/52 ≈ 98.5.
        XCTAssertEqual(dayZero.mean, (100.0 + 60 + 60) / 3, accuracy: 0.01)
        XCTAssertEqual(dayZero.doses, 3)
        XCTAssertEqual(dayZero.readings, 52)
    }

    func testAMetricWithOneBinIsNotDrawnAsAShape() {
        let regimen = doses(count: 3, everyDays: 7)
        let sameOffsetOnly = regimen.map {
            HealthMetricSample(type: .bloodPressureSystolic, value: 120,
                               start: $0.takenAt.addingTimeInterval(3600), source: .manual)
        }
        XCTAssertTrue(MedicationDoseResponse.folds(
            doses: regimen, samples: sameOffsetOnly, metrics: [.bloodPressureSystolic],
            now: now, calendar: utc).isEmpty,
            "one point is not a within-cycle shape")
    }

    func testSideEffectsFoldOntoTheSameAxisAsCounts() throws {
        let regimen = doses()
        // Nine records — the reader's real n — all in the day after a dose.
        let effects: [(name: String, severity: Int, date: Date)] = regimen.prefix(9).map {
            (name: "Nausea", severity: 4, date: $0.takenAt.addingTimeInterval(26 * 3600))
        }
        let fold = try XCTUnwrap(MedicationDoseResponse.sideEffectFold(
            doses: regimen, effects: effects, now: now))
        XCTAssertEqual(fold.cycleDays, 7)
        XCTAssertEqual(fold.recordCount, 9)
        XCTAssertEqual(fold.busiestOffset, 1)
        XCTAssertEqual(fold.counts.reduce(0, +), 9)
    }

    func testNoSideEffectsMeansNoFoldRatherThanAFlatOne() {
        XCTAssertNil(MedicationDoseResponse.sideEffectFold(doses: doses(), effects: [], now: now),
                     "seven empty bars claim a shape that was never measured")
    }
}
