import XCTest
@testable import InsightKit

private let metNow = TestClock.now
private let metCalendar = TestClock.utc

/// The metabolism card's arithmetic is simple and its honesty is not. These
/// tests are mostly about the second: what it refuses to say, and when it
/// refuses to say anything at all.
final class MetabolismTests: XCTestCase {

    /// A reader eating `intake` a day and losing `kgPerWeek`, logged on
    /// `loggedOfLast` of the last `days` days.
    private func samples(intake: Double = 2000, kgPerWeek: Double = -0.5,
                         days: Int = 28, loggedOfLast: Int? = nil,
                         logEvery: Int = 1,
                         startWeight: Double = 90, lean: Double? = 60,
                         active: Double? = 400) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let logged = loggedOfLast ?? days
        for day in 0..<days {
            let start = TestClock.day(day)
            // Weight, every day: the trend is the other half of the
            // back-calculation and needs a run of weigh-ins.
            out.append(.init(type: .bodyMass,
                             value: startWeight + kgPerWeek / 7 * Double(day) * -1,
                             start: start, source: .withings))
            if let lean {
                out.append(.init(type: .leanBodyMass, value: lean, start: start,
                                 source: .withings))
            }
            if let active {
                out.append(.init(type: .activeEnergyBurned, value: active, start: start,
                                 source: .appleHealth))
            }
            if day < logged && day % logEvery == 0 {
                out.append(.init(type: .dietaryEnergy, value: intake, start: start,
                                 source: .appleHealth))
            }
        }
        return out
    }

    private func evaluate(_ samples: [HealthMetricSample]) -> EnergyBalance? {
        EnergyBalanceModel.evaluate(samples: samples, profile: UserHealthProfile(),
                                    now: metNow, calendar: metCalendar)
    }

    // MARK: - The arithmetic

    /// Half a kilogram a week is 3,850 kcal a week, or 550 a day — so a reader
    /// eating 2,000 and losing that fast is burning about 2,550.
    func testExpenditureIsBackCalculatedFromIntakeAndTheScale() throws {
        let out = try XCTUnwrap(evaluate(samples(intake: 2000, kgPerWeek: -0.5)))
        // Exact, because the slope is fitted to the raw weigh-ins rather than
        // to a smoothed series — see `weightTrend`, where using the smoothed
        // one costs 150 kcal a day of expenditure and invents suppression.
        XCTAssertEqual(out.observedTDEE, 2550, accuracy: 5)
        XCTAssertEqual(out.intakeMean, 2000, accuracy: 1)
        XCTAssertGreaterThan(out.deficitPerDay, 0)
    }

    /// Gaining weight puts expenditure *below* intake — the sign has to survive
    /// the direction change, which is the easiest thing in this file to get
    /// backwards.
    func testGainingWeightPutsExpenditureBelowIntake() throws {
        let out = try XCTUnwrap(evaluate(samples(intake: 3000, kgPerWeek: 0.3)))
        XCTAssertLessThan(out.observedTDEE, 3000)
        XCTAssertLessThan(out.deficitPerDay, 0)
    }

    /// Katch-McArdle where lean mass exists, because that is the case it is
    /// better in — and it needs no age or sex, which is why the card can score
    /// a reader who has entered neither.
    func testLeanMassChoosesKatchMcArdleAndNeedsNoProfile() throws {
        let out = try XCTUnwrap(evaluate(samples(lean: 60)))
        XCTAssertEqual(try XCTUnwrap(out.basal),
                       EnergyBalanceModel.katchMcArdleBMR(leanKilograms: 60), accuracy: 0.5)
        XCTAssertTrue(try XCTUnwrap(out.basalMethod).contains("Katch"))
        XCTAssertNotNil(out.speed)
    }

    /// Prediction is resting + *measured* movement + the thermic effect of what
    /// was eaten — never a lifestyle multiplier off a dropdown.
    func testPredictionAddsMeasuredMovementAndTheThermicEffect() throws {
        let out = try XCTUnwrap(evaluate(samples(intake: 2000, lean: 60, active: 400)))
        let expected = EnergyBalanceModel.katchMcArdleBMR(leanKilograms: 60) + 400 + 200
        XCTAssertEqual(try XCTUnwrap(out.predictedTDEE), expected, accuracy: 5)
    }

    // MARK: - What it refuses to do

    /// **The gate.** Under-reporting is charged to metabolism by this
    /// arithmetic, so a diary with holes in it produces a flattering number,
    /// and the card would rather say nothing.
    func testAPatchyFoodLogIsNotJudgeable() throws {
        // Gaps *inside* the window — every third day missing — rather than a
        // later start, which is a reader logging well and is judged as such.
        let patchy = try XCTUnwrap(evaluate(samples(days: 28, logEvery: 2)))
        XCTAssertFalse(patchy.isJudgeable)
        let complete = try XCTUnwrap(evaluate(samples(days: 28)))
        XCTAssertTrue(complete.isJudgeable)
    }

    /// The card, not just the model: a reader below the gate gets an
    /// explanation and **no score**, rather than the most flattering reading of
    /// the least data.
    func testTheCardWithholdsTheNumberBelowTheGate() {
        let result = MetabolismInsight().evaluate(
            samples: samples(days: 28, logEvery: 2),
            profile: UserHealthProfile(), now: metNow)
        XCTAssertNil(result.score)
        // **Two claims, two asserts.** This was one disjunction —
        // `contains("flatter") || drivers.isEmpty` — under which the wording pin
        // could rot while the unrelated empty-drivers half kept it green, and
        // vice versa. Both halves are true of the shipped card, so both are
        // asserted.
        XCTAssertTrue(result.explanation.contains("flatter"),
                      "the card no longer says *why* it is withholding the number: "
                      + result.explanation)
        XCTAssertTrue(result.drivers.isEmpty,
                      "a card with no score must not still list drivers: \(result.drivers)")
    }

    /// A reader who started logging a fortnight ago and has logged every day
    /// since is logging perfectly — measuring them against a nominal 28 days
    /// would mark them down for the days before they started.
    func testCompletenessIsMeasuredOverTheReadersOwnLoggingWindow() throws {
        let out = try XCTUnwrap(evaluate(samples(days: 15, loggedOfLast: 15)))
        XCTAssertTrue(out.isJudgeable)
        XCTAssertEqual(out.windowDays, 15)
    }

    /// Two weeks is the floor. Below it water weight swamps the weight trend
    /// and the subtraction is noise.
    func testTooShortAWindowSaysNothing() {
        XCTAssertNil(evaluate(samples(days: 10, loggedOfLast: 10)))
    }

    /// **A ratio above prediction is not an achievement**, and the card says
    /// so before it says anything metabolic. The reader here eats 1,200 and
    /// loses 1.2 kg a week, which is arithmetically impossible on their size
    /// unless the log is missing meals.
    func testAFastReadingNamesTheFoodLogFirst() throws {
        let fixture = samples(intake: 1000, kgPerWeek: -2.0, lean: 60, active: 100)
        let out = try XCTUnwrap(evaluate(fixture))
        XCTAssertTrue(out.underLoggingSuspected)
        let result = MetabolismInsight().evaluate(
            samples: fixture, profile: UserHealthProfile(), now: metNow)
        let first = try XCTUnwrap(result.driverLines.first)
        XCTAssertTrue(first.text.contains("did not make it into the log"), first.text)
        XCTAssertEqual(first.isNotable, true)
    }

    /// Running *fast* is not scored as good: the curve holds at 100 rather than
    /// rewarding a number that usually means the diary is incomplete.
    func testTheScoreDoesNotRewardRunningAbovePrediction() {
        XCTAssertEqual(EnergyBalanceModel.score(speed: 1.0), 100, accuracy: 0.5)
        XCTAssertEqual(EnergyBalanceModel.score(speed: 1.3), 100, accuracy: 0.5)
        XCTAssertLessThan(EnergyBalanceModel.score(speed: 0.85), 60)
    }

    /// The published anchors, and no step anywhere along the curve — a band
    /// table rendered as a `switch` is the defect class this repo keeps paying
    /// for.
    func testTheScoreCurveHasNoStep() {
        var previous = EnergyBalanceModel.score(speed: 0.5)
        for i in 1...4000 {
            let speed = 0.5 + Double(i) / 4000 * 1.0
            let value = EnergyBalanceModel.score(speed: speed)
            XCTAssertLessThan(abs(value - previous), 1.0, "step at \(speed)")
            previous = value
        }
    }

    /// Nothing on this card claims a share of the answer: it is one equation
    /// with two terms, and percentages that sum to 100 would mean nothing.
    func testTheEquationsRowsCarryNoInventedShares() throws {
        let result = MetabolismInsight().evaluate(samples: samples(),
                                                  profile: UserHealthProfile(), now: metNow)
        XCTAssertFalse(result.contributors.isEmpty)
        for row in result.contributors {
            XCTAssertEqual(row.weight, 0, "\(row.metric) invented a share")
            XCTAssertFalse(row.detail.isEmpty)
        }
    }
}
