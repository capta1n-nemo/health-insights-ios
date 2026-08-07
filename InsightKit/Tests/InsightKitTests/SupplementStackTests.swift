import XCTest
@testable import InsightKit

/// **The stack card's arithmetic, and the three things it must never do.**
///
/// Every test here is one of: an unknown becoming a zero, a unit being guessed,
/// or a limit being resolved against a profile the app does not have. Those are
/// the three ways this feature could be quietly wrong — quietly, because the
/// output would still be a plausible number beside a real published figure.
final class SupplementStackTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// A 41-year-old male, the same fixture shape `SyntheticSeed` uses.
    private func profile(sex: BiologicalSex = .male, age: Double = 41) -> UserHealthProfile {
        var profile = UserHealthProfile()
        profile.set(.init(kind: .dateOfBirth,
                          value: now.addingTimeInterval(-age * 365.2425 * 86_400)
                              .timeIntervalSince1970,
                          recordedAt: now))
        profile.set(.init(kind: .biologicalSex, value: sex == .male ? 0 : 1, recordedAt: now))
        return profile
    }

    private func entry(_ name: String, _ ingredients: [SupplementIngredient],
                       servings: Double = 1) -> SupplementEntry {
        SupplementEntry(product: SupplementProduct(name: name, ingredients: ingredients),
                        servingsPerDay: servings,
                        startedOn: now.addingTimeInterval(-30 * 86_400))
    }

    private func stated(_ nutrient: Nutrient, _ value: Double, _ unit: NutrientUnit,
                        form: NutrientForm? = nil) -> SupplementIngredient {
        SupplementIngredient(nutrient: nutrient, labelText: nutrient.displayName,
                             amount: .stated(.init(value: value, unit: unit, form: form)))
    }

    // MARK: - The sum across the stack, which is the whole feature

    /// **The finding this card exists for.** Two ordinary products, each well
    /// under the zinc limit, that together are over it.
    func testTwoUnremarkableProductsCanExceedALimitTogether() throws {
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Multivitamin", [stated(.zinc, 25, .milligrams)]),
                      entry("Immune support", [stated(.zinc, 25, .milligrams)])],
            profile: profile(), now: now))

        let zinc = try XCTUnwrap(stack.totals.first { $0.nutrient == .zinc })
        XCTAssertEqual(zinc.fromSupplements, 50, accuracy: 1e-9)
        XCTAssertEqual(zinc.contributingProducts.count, 2)
        // The adult UL is 40 mg.
        XCTAssertTrue(zinc.isAtOrOverLimit)
        XCTAssertEqual(try XCTUnwrap(zinc.shareOfLimit), 1.25, accuracy: 1e-9)
    }

    func testServingsPerDayMultiplyTheLabel() throws {
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Powder", [stated(.magnesium, 200, .milligrams)], servings: 2)],
            profile: profile(), now: now))
        XCTAssertEqual(try XCTUnwrap(stack.totals.first).fromSupplements, 400, accuracy: 1e-9)
    }

    func testAStoppedProductIsNotInTheTotal() {
        var stopped = entry("Old bottle", [stated(.zinc, 50, .milligrams)])
        stopped.stoppedOn = now.addingTimeInterval(-86_400)
        XCTAssertNil(SupplementStackModel.evaluate(entries: [stopped],
                                                   profile: profile(), now: now))
    }

    // MARK: - ⚠️ An unknown is never a zero

    func testAProprietaryBlendIsCarriedAsUnknownRatherThanNought() throws {
        let blend = SupplementIngredient(
            nutrient: .selenium, labelText: "Selenium",
            amount: .withinProprietaryBlend(blendName: "Antioxidant Blend",
                                            blendTotal: .init(value: 250, unit: .milligrams)))
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Blendy", [blend])], profile: profile(), now: now))

        let selenium = try XCTUnwrap(stack.totals.first { $0.nutrient == .selenium })
        XCTAssertFalse(selenium.isComplete, "a blend leaves the total incomplete")
        XCTAssertEqual(selenium.unresolved.count, 1)
        XCTAssertEqual(stack.unresolvedCount, 1)
        XCTAssertTrue(selenium.unresolved[0].reason.contains("floor"),
                      selenium.unresolved[0].reason)
    }

    /// ⚠️ **The blend's own total is not divided into its ingredients.** 250 mg
    /// across an unknown number of them is not 250 mg of selenium, and this is
    /// the one place that could plausibly have been "helpful".
    func testABlendTotalIsNeverAttributedToOneIngredient() throws {
        let blend = SupplementIngredient(
            nutrient: .selenium, labelText: "Selenium",
            amount: .withinProprietaryBlend(blendName: "Blend",
                                            blendTotal: .init(value: 250, unit: .milligrams)))
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Blendy", [blend])], profile: profile(), now: now))
        XCTAssertEqual(try XCTUnwrap(stack.totals.first).fromSupplements, 0,
                       "the blend total must not become the ingredient's amount")
    }

    func testAnIngredientListedWithNoAmountIsUnresolvedRatherThanAbsent() throws {
        let line = SupplementIngredient(nutrient: .iodine, labelText: "Kelp (iodine)",
                                        amount: .notStated)
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Kelp", [line])], profile: profile(), now: now))
        let iodine = try XCTUnwrap(stack.totals.first { $0.nutrient == .iodine })
        XCTAssertFalse(iodine.isComplete)
        XCTAssertEqual(iodine.unresolved.count, 1)
    }

    /// An unrecognised line is counted and kept, not silently dropped.
    func testAnUnrecognisedIngredientIsCountedRatherThanDropped() throws {
        let herb = SupplementIngredient(nutrient: nil, labelText: "Ashwagandha",
                                        amount: .stated(.init(value: 600, unit: .milligrams)))
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Herbal", [herb, stated(.zinc, 5, .milligrams)])],
            profile: profile(), now: now))
        XCTAssertEqual(stack.unrecognisedIngredientCount, 1)
        XCTAssertEqual(stack.totals.count, 1, "only the nutrient is weighed")
    }

    // MARK: - ⚠️ A unit is never guessed

    func testVitaminDConvertsFromIUWithoutTheForm() throws {
        let result = NutrientAmount(value: 4_000, unit: .internationalUnits)
            .converted(to: .vitaminD)
        XCTAssertEqual(try result.get(), 100, accuracy: 1e-9)
    }

    /// 1 mg is 1.49 IU natural and 2.22 IU synthetic — a 49% ambiguity, which is
    /// far too much to pick a side on.
    func testVitaminEInIUWithNoFormRefusesRatherThanPicking() {
        let result = NutrientAmount(value: 400, unit: .internationalUnits)
            .converted(to: .vitaminE)
        guard case .failure(.formNotStated) = result else {
            return XCTFail("expected a refusal, got \(result)")
        }
    }

    func testVitaminEConvertsOnceTheFormIsNamed() throws {
        let natural = NutrientAmount(value: 400, unit: .internationalUnits,
                                     form: .naturalVitaminE).converted(to: .vitaminE)
        let synthetic = NutrientAmount(value: 400, unit: .internationalUnits,
                                       form: .syntheticVitaminE).converted(to: .vitaminE)
        XCTAssertEqual(try natural.get(), 400 / 1.49, accuracy: 1e-6)
        XCTAssertEqual(try synthetic.get(), 400 / 2.22, accuracy: 1e-6)
    }

    func testVitaminAInIUWithNoFormRefuses() {
        let result = NutrientAmount(value: 5_000, unit: .internationalUnits)
            .converted(to: .vitaminA)
        guard case .failure(.formNotStated) = result else {
            return XCTFail("expected a refusal, got \(result)")
        }
    }

    /// ⚠️ **Beta-carotene converts to nought, and that zero is not a guess** —
    /// the vitamin A upper limit is defined to exclude it.
    func testBetaCaroteneCarriesNoneOfTheVitaminALimit() throws {
        let result = NutrientAmount(value: 10_000, unit: .internationalUnits,
                                    form: .betaCarotene).converted(to: .vitaminA)
        XCTAssertEqual(try result.get(), 0)
    }

    /// A supplement's folic acid is counted as twice its mass in DFE, so a
    /// label in DFE halves on the way to the unit the limit is written in.
    func testFolateDFEHalvesToFolicAcid() throws {
        let result = NutrientAmount(value: 800, unit: .microgramsDFE).converted(to: .folate)
        XCTAssertEqual(try result.get(), 400, accuracy: 1e-9)
    }

    func testAnUnconvertibleAmountBecomesUnresolvedRatherThanMissing() throws {
        let line = SupplementIngredient(
            nutrient: .vitaminE, labelText: "Vitamin E",
            amount: .stated(.init(value: 400, unit: .internationalUnits)))
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("E", [line])], profile: profile(), now: now))
        let e = try XCTUnwrap(stack.totals.first { $0.nutrient == .vitaminE })
        XCTAssertEqual(e.fromSupplements, 0)
        XCTAssertFalse(e.isComplete, "an unconvertible line must not vanish")
        XCTAssertTrue(e.unresolved[0].reason.contains("IU"), e.unresolved[0].reason)
    }

    // MARK: - ⚠️ A limit is never resolved against a profile the app lacks

    func testNoProfileMeansNoComparisonRatherThanADefaultBand() throws {
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Multi", [stated(.zinc, 50, .milligrams)])],
            profile: UserHealthProfile(), now: now))
        let zinc = try XCTUnwrap(stack.totals.first)
        guard case .outsideTable = zinc.limit else {
            return XCTFail("expected no limit without a profile, got \(zinc.limit)")
        }
        XCTAssertNil(zinc.shareOfLimit)
        XCTAssertNil(stack.score, "a stack the app cannot weigh must not be scored")
    }

    func testAReaderUnderFourteenIsRefusedRatherThanGivenAnAdultCeiling() {
        let resolution = NutrientUpperLimits.limit(for: .zinc, sex: .male, age: 9)
        guard case .outsideTable(let reason) = resolution else {
            return XCTFail("expected a refusal, got \(resolution)")
        }
        XCTAssertTrue(reason.contains("14"), reason)
    }

    /// Calcium drops at 51 and phosphorus at 71 — the two limits that genuinely
    /// move with age among adults.
    func testTheTwoAgeVaryingAdultLimitsActuallyVary() {
        XCTAssertEqual(NutrientUpperLimits.limit(for: .calcium, sex: .female, age: 40),
                       .limit(2_500))
        XCTAssertEqual(NutrientUpperLimits.limit(for: .calcium, sex: .female, age: 60),
                       .limit(2_000))
        XCTAssertEqual(NutrientUpperLimits.limit(for: .phosphorus, sex: .male, age: 60),
                       .limit(4_000))
        XCTAssertEqual(NutrientUpperLimits.limit(for: .phosphorus, sex: .male, age: 80),
                       .limit(3_000))
    }

    /// **The sex-specific half.** No adult UL varies by sex; the recommended
    /// intakes do, and iron is the starkest case — which is why the card needs
    /// sex even though the ceiling does not.
    func testTheLimitDoesNotVaryBySexAndTheRecommendationDoes() {
        XCTAssertEqual(NutrientUpperLimits.limit(for: .iron, sex: .male, age: 30),
                       NutrientUpperLimits.limit(for: .iron, sex: .female, age: 30))
        XCTAssertEqual(NutrientUpperLimits.recommendedIntake(for: .iron, sex: .male, age: 30),
                       .rda(8))
        XCTAssertEqual(NutrientUpperLimits.recommendedIntake(for: .iron, sex: .female, age: 30),
                       .rda(18))
    }

    /// Every nutrient this app can weigh either has a limit in the table or
    /// declares `noLimitPublished` — and the two can never disagree, because a
    /// nutrient with a basis and no row would silently report "no limit".
    func testTheLimitTableAgreesWithEveryNutrientsDeclaredBasis() {
        for nutrient in Nutrient.allCases {
            let hasRow = NutrientUpperLimits.upperLimits[nutrient]?[.adult19to50] != nil
            switch nutrient.limitBasis {
            case .noLimitPublished:
                XCTAssertFalse(hasRow, "\(nutrient) declares no limit and has one")
            case .totalIntake, .supplementalOnly:
                XCTAssertTrue(hasRow, "\(nutrient) declares a limit basis and has no row")
            }
        }
    }

    // MARK: - Food, where the limit is about food

    func testAMagnesiumFoodLogIsNeverAddedToASupplementalLimit() throws {
        let food = (0..<10).map {
            HealthMetricSample(type: .dietaryMagnesium, value: 300,
                               start: now.addingTimeInterval(-Double($0) * 86_400),
                               source: .appleHealth)
        }
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Mg", [stated(.magnesium, 200, .milligrams)])],
            samples: food, profile: profile(), now: now))
        let magnesium = try XCTUnwrap(stack.totals.first)
        XCTAssertEqual(magnesium.fromFood, 0)
        XCTAssertFalse(magnesium.countsFood,
                       "the magnesium UL is a limit on supplemental magnesium only")
        XCTAssertEqual(magnesium.countedTotal, 200, accuracy: 1e-9)
    }

    func testACalciumFoodLogIsAddedBecauseThatLimitCoversFood() throws {
        let food = (0..<10).map {
            HealthMetricSample(type: .dietaryCalcium, value: 800,
                               start: now.addingTimeInterval(-Double($0) * 86_400),
                               source: .appleHealth)
        }
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Cal", [stated(.calcium, 1_000, .milligrams)])],
            samples: food, profile: profile(), now: now))
        let calcium = try XCTUnwrap(stack.totals.first)
        XCTAssertTrue(calcium.countsFood)
        XCTAssertEqual(calcium.fromFood, 800, accuracy: 1e-9)
        XCTAssertEqual(calcium.countedTotal, 1_800, accuracy: 1e-9)
    }

    /// ⚠️ Below the floor nothing is assumed — a two-day log is not a diet.
    func testTooFewLoggedDaysMeansNoFoodFigureRatherThanASmallOne() throws {
        let food = (0..<2).map {
            HealthMetricSample(type: .dietaryCalcium, value: 800,
                               start: now.addingTimeInterval(-Double($0) * 86_400),
                               source: .appleHealth)
        }
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Cal", [stated(.calcium, 1_000, .milligrams)])],
            samples: food, profile: profile(), now: now))
        let calcium = try XCTUnwrap(stack.totals.first)
        XCTAssertFalse(calcium.countsFood)
        XCTAssertEqual(calcium.countedTotal, 1_000, accuracy: 1e-9)
        XCTAssertEqual(calcium.foodDaysLogged, 2, "the count is still reported")
    }

    /// The canonical unit of every nutrient with a food series must match the
    /// unit that series is measured in, or the sum is out by a thousand.
    func testFoodSeriesAreInTheCanonicalUnit() {
        let expected: [Nutrient: String] = [
            .calcium: "mg", .iron: "mg", .zinc: "mg", .vitaminC: "mg",
            .magnesium: "mg", .vitaminD: "mcg", .vitaminA: "mcg RAE",
            .vitaminB12: "mcg",
        ]
        for (nutrient, unit) in expected {
            let metric = nutrient.dietaryMetric
            XCTAssertNotNil(metric, "\(nutrient) lost its dietary metric")
            XCTAssertEqual(nutrient.canonicalUnit.symbol, unit, "\(nutrient)")
        }
    }

    // MARK: - Scoring

    func testTheCurveIsContinuousAcrossTheLimit() {
        var previous = SupplementStackModel.curve(share: 0)
        for step in 1...4_000 {
            let share = Double(step) / 800
            let score = SupplementStackModel.curve(share: share)
            XCTAssertLessThan(abs(score - previous), 1,
                              "a step at share \(share): \(previous) → \(score)")
            previous = score
        }
    }

    /// Sitting exactly on a published upper limit is not "good" — there is no
    /// headroom left, and a green card would be congratulating somebody at the
    /// ceiling. Same call `SoundExposureModel` makes about the WHO allowance.
    func testSittingExactlyOnALimitIsNotGood() {
        let score = SupplementStackModel.curve(share: 1.0)
        XCTAssertLessThan(score, ScoreBand.goodFloor)
        XCTAssertGreaterThan(score, ScoreBand.fairFloor)
    }

    func testTheWorstNutrientSetsTheNumberRatherThanTheAverage() throws {
        let overOnly = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("A", [stated(.zinc, 80, .milligrams)])],
            profile: profile(), now: now))
        let overPlusNine = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("A", [stated(.zinc, 80, .milligrams),
                                  stated(.vitaminC, 10, .milligrams),
                                  stated(.selenium, 10, .micrograms),
                                  stated(.iodine, 10, .micrograms)])],
            profile: profile(), now: now))
        let a = try XCTUnwrap(overOnly.score)
        let b = try XCTUnwrap(overPlusNine.score)
        XCTAssertEqual(a, b, accuracy: 3,
                       "three unremarkable nutrients must not average away one at "
                           + "twice its limit")
    }

    func testAStackFarUnderEveryLimitScoresWell() throws {
        let stack = try XCTUnwrap(SupplementStackModel.evaluate(
            entries: [entry("Gentle", [stated(.vitaminC, 100, .milligrams)])],
            profile: profile(), now: now))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(stack.score), ScoreBand.goodFloor)
    }

    // MARK: - The card

    func testTheEmptyCardAsksForSomethingRatherThanSayingNoData() {
        let result = SupplementStackInsight().evaluate(
            samples: [], profile: profile(), now: now)
        XCTAssertTrue(result.invitesInput)
        XCTAssertNotEqual(result.headline, "No data yet")
        XCTAssertTrue(result.isWorthShowing)
    }

    func testACardWithAStackAndNoProfileStillShowsTheStack() {
        let card = SupplementStackInsight(
            entries: [entry("Multi", [stated(.zinc, 50, .milligrams)])])
        let result = card.evaluate(samples: [], profile: UserHealthProfile(), now: now)
        XCTAssertNil(result.score)
        XCTAssertFalse(result.unmetRequirements.isEmpty,
                       "it must say which facts it is waiting for")
        XCTAssertTrue(result.isWorthShowing)
        XCTAssertFalse(result.drivers.isEmpty, "a visible card must say something")
    }

    func testTheCardNamesTheNutrientAndThePublishedFigure() throws {
        let card = SupplementStackInsight(
            entries: [entry("Multi", [stated(.zinc, 50, .milligrams)])])
        let result = card.evaluate(samples: [], profile: profile(), now: now)
        let lead = try XCTUnwrap(result.drivers.first)
        XCTAssertTrue(lead.contains("Zinc"), lead)
        XCTAssertTrue(lead.contains("40 mg"), "the published limit has to appear: \(lead)")
        XCTAssertNotNil(result.score)
    }

    /// Every derived weight must name a series the same result produces — the
    /// rule `DerivedFactorIdentityTests` enforces across the registry, checked
    /// here too because this card emits one series per nutrient.
    func testEveryWeightedFactorNamesASeriesTheCardProduces() {
        let card = SupplementStackInsight(
            entries: [entry("Multi", [stated(.zinc, 50, .milligrams),
                                      stated(.iron, 20, .milligrams)])])
        let result = card.evaluate(samples: [], profile: profile(), now: now)
        let produced = Set(result.derivedOutputs.map {
            DerivedSeriesID(.supplementStack, $0.key)
        })
        for factor in result.otherFactors {
            let id = factor.derivedSeries
            XCTAssertNotNil(id, "\(factor.name) is not a derived factor")
            if let id { XCTAssertTrue(produced.contains(id), "\(id) is produced by nothing") }
        }
    }

    func testSharesSumToOneWhenAnythingIsDeducting() {
        let card = SupplementStackInsight(
            entries: [entry("Multi", [stated(.zinc, 50, .milligrams),
                                      stated(.iron, 40, .milligrams)])])
        let result = card.evaluate(samples: [], profile: profile(), now: now)
        XCTAssertEqual(result.weightedFactors.reduce(0) { $0 + $1.weight }, 1,
                       accuracy: 1e-9)
    }
}

/// **The wording rule, held by a test rather than by review.**
///
/// The reader's constraint on this card, and the one property of it that would
/// be actively harmful to lose in a later edit: *exceeding an upper limit is
/// information, not medical advice.* The card states the number and the
/// published limit. It does not tell anyone to stop.
final class SupplementStackWordingTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    /// Phrases that would turn a report into an instruction. Deliberately
    /// includes the gentle ones — "consider reducing" is still advice.
    private let forbidden = [
        "you should", "you must", "stop taking", "reduce your", "cut back",
        "consider reducing", "consult", "see a doctor", "talk to your",
        "is dangerous", "is unsafe", "is harmful", "risk of toxicity",
        "we recommend", "advise",
    ]

    private func profile() -> UserHealthProfile {
        var profile = UserHealthProfile()
        profile.set(.init(kind: .dateOfBirth,
                          value: now.addingTimeInterval(-41 * 365.2425 * 86_400)
                              .timeIntervalSince1970, recordedAt: now))
        profile.set(.init(kind: .biologicalSex, value: 0, recordedAt: now))
        return profile
    }

    /// A stack well over three limits at once — the state most likely to tempt
    /// a later edit into adding a warning.
    private func loudStack() -> [SupplementEntry] {
        [SupplementEntry(
            product: SupplementProduct(name: "Heavy", ingredients: [
                SupplementIngredient(nutrient: .zinc, labelText: "Zinc",
                                     amount: .stated(.init(value: 120, unit: .milligrams))),
                SupplementIngredient(nutrient: .selenium, labelText: "Selenium",
                                     amount: .stated(.init(value: 900, unit: .micrograms))),
                SupplementIngredient(nutrient: .vitaminB6, labelText: "B6",
                                     amount: .stated(.init(value: 300, unit: .milligrams))),
                SupplementIngredient(nutrient: .iodine, labelText: "Iodine",
                                     amount: .withinProprietaryBlend(
                                        blendName: "Thyroid Blend", blendTotal: nil)),
            ]),
            startedOn: now.addingTimeInterval(-30 * 86_400))]
    }

    func testNothingThisCardSaysIsAnInstruction() {
        let result = SupplementStackInsight(entries: loudStack())
            .evaluate(samples: [], profile: profile(), now: now)
        var text = ([result.headline, result.subheadline ?? "", result.explanation]
                    + result.drivers
                    + result.otherFactors.map(\.detail)
                    + result.contributors.map(\.detail)).joined(separator: " ")
        text = text.lowercased()
        for phrase in forbidden {
            XCTAssertFalse(text.contains(phrase),
                           "this card gave an instruction: \"\(phrase)\"")
        }
    }

    /// The other half: it must still say the number and the published figure,
    /// or the restraint above would be satisfied by saying nothing.
    func testItStillNamesTheTotalAndThePublishedLimit() {
        let result = SupplementStackInsight(entries: loudStack())
            .evaluate(samples: [], profile: profile(), now: now)
        let text = result.drivers.joined(separator: " ")
        XCTAssertTrue(text.contains("120 mg"), text)
        XCTAssertTrue(text.contains("upper limit"), text)
    }

    /// ⚠️ And the unknown must be visible in the prose, not only in a field —
    /// a proprietary blend that no sentence mentions is a floor the reader
    /// cannot know about.
    func testTheProseSaysWhenATotalIsAFloor() {
        let result = SupplementStackInsight(entries: loudStack())
            .evaluate(samples: [], profile: profile(), now: now)
        let text = result.drivers.joined(separator: " ")
        XCTAssertTrue(text.contains("at least"), text)
        XCTAssertTrue(text.lowercased().contains("proprietary blend"), text)
    }

    /// The absence of a published limit must never be printed as reassurance.
    func testNoPublishedLimitIsNeverPrintedAsSafety() {
        let caution = NutrientUpperLimits.noLimitCaution.lowercased()
        XCTAssertTrue(caution.contains("not enough evidence"), caution)
        XCTAssertTrue(caution.contains("not a finding that any amount is safe"), caution)
    }
}
