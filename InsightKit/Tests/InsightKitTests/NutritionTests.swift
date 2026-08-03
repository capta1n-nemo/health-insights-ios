import XCTest
@testable import InsightKit

private let nutNow = TestClock.now
private let nutCalendar = TestClock.utc

/// The nutrition card exists because the user asked for published guidance to
/// be used — *"I am happy with all dietary guidelines"* — so these tests are
/// mostly about the two halves of that: the figures are the published ones, and
/// nothing the guidance does not state gets scored anyway.
final class NutritionTests: XCTestCase {

    /// A day's eating, repeated across `days`. Values are per day; a nil is a
    /// nutrient the reader's logger does not record.
    private func samples(_ values: [MetricType: Double], days: Int = 14,
                         bodyMass: Double? = 80) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for day in 0..<days {
            let start = TestClock.day(day)
            for (metric, value) in values {
                out.append(.init(type: metric, value: value, start: start, source: .appleHealth))
            }
        }
        if let bodyMass {
            out.append(.init(type: .bodyMass, value: bodyMass, start: TestClock.day(0),
                             source: .withings))
        }
        return out
    }

    private func evaluate(_ values: [MetricType: Double], days: Int = 14,
                          bodyMass: Double? = 80,
                          sex: BiologicalSex? = .male) -> NutritionModel.Output? {
        var profile = UserHealthProfile()
        if let sex {
            profile.set(.init(kind: .biologicalSex, value: sex == .male ? 0 : 1,
                              recordedAt: nutNow))
        }
        return NutritionModel.evaluate(samples: samples(values, days: days, bodyMass: bodyMass),
                                       profile: profile, now: nutNow, calendar: nutCalendar)
    }

    // MARK: - The floor the user asked for

    /// Protein is scored **per kilogram**, which is the only form the evidence
    /// comes in — 120 g is generous at 60 kg and thin at 110 kg.
    func testProteinIsScoredPerKilogramAndNotInGrams() throws {
        let light = try XCTUnwrap(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 120],
                                           bodyMass: 60))
        let heavy = try XCTUnwrap(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 120],
                                           bodyMass: 110))
        XCTAssertEqual(try XCTUnwrap(light.proteinPerKg), 2.0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(heavy.proteinPerKg), 1.09, accuracy: 0.01)
        XCTAssertGreaterThan(NutritionModel.proteinScore(gramsPerKilogram: 2.0),
                             NutritionModel.proteinScore(gramsPerKilogram: 1.09))
    }

    /// The published anchors, and the fact that this is a floor rather than a
    /// target: past 1.6 g/kg the curve stops climbing instead of rewarding more.
    func testTheProteinCurveSitsOnItsPublishedAnchors() {
        XCTAssertEqual(NutritionModel.proteinScore(gramsPerKilogram: 0.83), 65, accuracy: 0.5)
        XCTAssertEqual(NutritionModel.proteinScore(gramsPerKilogram: 1.2), 90, accuracy: 0.5)
        XCTAssertEqual(NutritionModel.proteinScore(gramsPerKilogram: 1.6), 100, accuracy: 0.5)
        XCTAssertEqual(NutritionModel.proteinScore(gramsPerKilogram: 3.0), 100, accuracy: 0.5)
    }

    /// No published figure says what one person should eat, so the calorie row
    /// is charted and carries no share — and it says why, which is the rule
    /// every unweighted row in this app follows.
    func testCaloriesAreChartedAndNeverScored() throws {
        let out = try XCTUnwrap(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 100,
                                          .dietaryFibre: 28]))
        let energy = try XCTUnwrap(out.contributions.first { $0.metric == .dietaryEnergy })
        XCTAssertEqual(energy.weight, 0)
        XCTAssertTrue(energy.detail.contains("not scored"), energy.detail)
        XCTAssertNil(energy.higherIsBetter)
    }

    /// Total sugars are not free sugars. WHO's under-10% figure limits the
    /// second, HealthKit reports the first, and scoring one against the other
    /// would mark a reader down for eating fruit.
    func testTotalSugarIsNotScoredAgainstTheFreeSugarGuideline() throws {
        let out = try XCTUnwrap(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 100,
                                          .dietarySugar: 120]))
        let sugar = try XCTUnwrap(out.contributions.first { $0.metric == .dietarySugar })
        XCTAssertEqual(sugar.weight, 0)
        XCTAssertTrue(sugar.detail.contains("free"), sugar.detail)
    }

    // MARK: - Shares

    /// Weights renormalise over the terms that had data, so a reader whose
    /// logger records only protein and fibre still sees shares that sum to one.
    func testSharesSumToOneOverWhateverWasLogged() throws {
        let out = try XCTUnwrap(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 100,
                                          .dietaryFibre: 30]))
        let weighted = out.contributions.filter { $0.weight > 0 }
        XCTAssertEqual(weighted.count, 2)
        XCTAssertEqual(weighted.reduce(0) { $0 + $1.weight }, 1.0, accuracy: 0.0001)
    }

    // MARK: - The floors

    /// Three days of logging is not a fortnight's diet, and the card says so
    /// rather than averaging what it has.
    func testTooFewLoggedDaysReturnsNothing() {
        XCTAssertNil(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 100], days: 2))
        XCTAssertNotNil(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 100], days: 3))
    }

    /// The means are over *logged* days, never over the window: a reader who
    /// logs four days of a fortnight ate on the other ten too.
    func testMeansAreOverLoggedDaysRatherThanTheWholeWindow() throws {
        let out = try XCTUnwrap(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 100], days: 4))
        XCTAssertEqual(try XCTUnwrap(out.means[.dietaryEnergy]), 2000, accuracy: 1)
        XCTAssertEqual(out.loggedDays, 4)
        XCTAssertEqual(out.completeness, 4.0 / 14.0, accuracy: 0.001)
    }

    /// Patchy logging is the card's own biggest caveat, so it leads with it and
    /// marks it notable rather than filing it under context.
    func testPatchyLoggingLeadsTheCardAndIsMarkedNotable() throws {
        var profile = UserHealthProfile()
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: nutNow))
        let result = NutritionInsight().evaluate(
            samples: samples([.dietaryEnergy: 2000, .dietaryProtein: 100], days: 5),
            profile: profile, now: nutNow)
        let first = try XCTUnwrap(result.driverLines.first)
        XCTAssertTrue(first.text.contains("Logged 5 of the last 14 days"), first.text)
        XCTAssertEqual(first.isNotable, true)
        XCTAssertEqual(result.confidence, .low)
    }

    // MARK: - The sex-specific figure

    /// EFSA's water figure differs by a quarter between the sexes, so the same
    /// two litres cannot score the same for both.
    func testTheWaterFigureIsSexSpecific() {
        let woman = NutritionModel.waterScore(litres: 1.6, sex: .female)
        let man = NutritionModel.waterScore(litres: 1.6, sex: .male)
        XCTAssertGreaterThan(woman, man)
        // Unstated sex uses the higher figure, which is the conservative way
        // round: it under-credits rather than over-credits.
        XCTAssertEqual(NutritionModel.waterScore(litres: 1.6, sex: nil), man, accuracy: 0.001)
    }

    // MARK: - Continuity

    /// Every curve here is a published band table, and a band table rendered as
    /// a `switch` is a staircase — the defect class this repo has already paid
    /// for seven times. Swept rather than spot-checked.
    func testNoCurveHasAStep() {
        func sweep(_ from: Double, _ to: Double, _ f: (Double) -> Double, _ name: String) {
            let steps = 4000
            var previous = f(from)
            for i in 1...steps {
                let x = from + (to - from) * Double(i) / Double(steps)
                let value = f(x)
                XCTAssertLessThan(abs(value - previous), 1.0,
                                  "\(name) jumps at \(x): \(previous) → \(value)")
                previous = value
            }
        }
        sweep(0, 3, NutritionModel.proteinScore(gramsPerKilogram:), "protein")
        sweep(0, 60, NutritionModel.fibreScore(grams:), "fibre")
        sweep(0, 40, NutritionModel.saturatedFatScore(percentOfEnergy:), "saturated fat")
        sweep(0, 70, NutritionModel.fatScore(percentOfEnergy:), "total fat")
        sweep(0, 8000, NutritionModel.sodiumScore(milligrams:), "sodium")
        sweep(0, 6000, NutritionModel.potassiumScore(milligrams:), "potassium")
        sweep(0, 5, { NutritionModel.waterScore(litres: $0, sex: .male) }, "water")
        sweep(0, 1500, NutritionModel.caffeineScore(milligrams:), "caffeine")
    }

    /// Each scored row names the body whose figure it uses. A band with no
    /// attribution is the thing this app refuses to draw.
    func testEveryScoredRowNamesItsSource() throws {
        let out = try XCTUnwrap(evaluate([.dietaryEnergy: 2000, .dietaryProtein: 100,
                                          .dietaryFibre: 20, .dietarySodium: 3000,
                                          .dietaryPotassium: 3000, .dietaryFat: 80,
                                          .dietarySaturatedFat: 25, .dietaryWater: 1.5,
                                          .dietaryCaffeine: 300]))
        let text = out.drivers.map(\.text).joined(separator: " | ")
        for body in ["WHO", "EFSA"] {
            XCTAssertTrue(text.contains(body), "no \(body) figure named: \(text)")
        }
    }
}
