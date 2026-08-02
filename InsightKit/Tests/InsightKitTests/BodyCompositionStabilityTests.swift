import XCTest
@testable import InsightKit

/// Body Composition's number must move because the **body** moved.
///
/// From the reader's export, four consecutive days of the score-over-time
/// chart: `07-30 49  07-31 15  08-01 15  08-02 55`. A crater and a full
/// recovery inside three days, on a card whose subject changes by grams a week.
/// Nobody's body did that.
///
/// The cause is measured in `testTheQualityTermNoLongerSwitchesInAtFullWeight`
/// and explained on `CompositionVelocity.changeConfidence`: a hard threshold on
/// a fitted slope, with a term scoring 4 out of 100 switching in and out across
/// it at its full 25% weight.
final class BodyCompositionStabilityTests: XCTestCase {

    private var profile: UserHealthProfile {
        let born = TestClock.utc.date(byAdding: .year, value: -40, to: TestClock.now)!
        var p = UserHealthProfile()
        p.set(.init(kind: .dateOfBirth, value: born.timeIntervalSince1970,
                    recordedAt: TestClock.now))
        p.set(.init(kind: .biologicalSex, value: 0, recordedAt: TestClock.now))
        return p
    }

    /// Ninety days of a body losing a perfectly steady 0.02 kg a day, weighed
    /// daily on a scale with the water swing every real scale has.
    private func samples(bodyFatOn fatDays: Set<Int>) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        for day in stride(from: 89, through: 0, by: -1) {
            let date = TestClock.utc.date(byAdding: .day, value: -day, to: TestClock.now)!
            let weight = 110.5 - Double(89 - day) * 0.02 + Double(day % 4) * 0.4
            out.append(.init(type: .height, value: 1.85, start: date, source: .appleHealth))
            out.append(.init(type: .bodyMass, value: weight, start: date, source: .withings))
            out.append(.init(type: .leanBodyMass, value: weight * 0.68,
                             start: date, source: .withings))
            if fatDays.contains(day) {
                out.append(.init(type: .bodyFatPercentage, value: 32.0,
                                 start: date, source: .withings))
            }
        }
        return out
    }

    private func confidence(_ percentPerWeek: Double) -> Double {
        CompositionVelocity(windowDays: 56, kilogramsPerWeek: percentPerWeek,
                            percentPerWeek: percentPerWeek, leanKilogramsPerWeek: nil,
                            leanShareOfChange: nil, residualSD: 0,
                            weighIns: 56, latestWeight: 100)
            .changeConfidence
    }

    /// **The regression.** Four consecutive days, one steadily-shrinking body.
    ///
    /// Before the ramp this produced `36 · 50 · 46 · 37` — a 14-point lurch
    /// with nothing behind it. What is left is the level and rate terms
    /// responding to the water swing, which is real and small.
    func testConsecutiveDaysDoNotLurch() throws {
        let history = samples(bodyFatOn: Set(2...89))
        let scores: [Double] = try [3, 2, 1, 0].map { daysAgo in
            let asOf = TestClock.utc.date(byAdding: .day, value: -daysAgo, to: TestClock.now)!
            let result = BodyCompositionInsight().evaluate(
                samples: history.filter { $0.start <= asOf }, profile: profile, now: asOf)
            return try XCTUnwrap(result.score)
        }
        let jumps = zip(scores, scores.dropFirst()).map { abs($1 - $0) }
        XCTAssertLessThan(jumps.max() ?? 0, 6,
            "day-to-day scores lurched: \(scores.map { Int($0.rounded()) })")
    }

    /// The mechanism, pinned at the arithmetic rather than through the card:
    /// slopes either side of the stable band must not swing the quality term's
    /// weight from nothing to everything.
    func testTheQualityTermNoLongerSwitchesInAtFullWeight() {
        // The four slopes the fixture above actually produced, in %/week. Two
        // clear the 0.1 stable band and two do not, which is precisely what
        // used to switch the term in and out.
        let weights = [-0.127, -0.096, -0.068, -0.162].map(confidence)
        XCTAssertTrue(weights.allSatisfy { $0 < 0.3 },
                      "marginal slopes still carry near-full weight: \(weights)")
        XCTAssertLessThan((weights.max() ?? 0) - (weights.min() ?? 0), 0.3,
                          "crossing the band is still a cliff: \(weights)")
    }

    /// The ramp is 0 inside the band, 1 at a rate nobody would call noise, and
    /// monotone in between — so it can never introduce a cliff of its own.
    func testTheRampIsMonotoneAndBounded() {
        XCTAssertEqual(confidence(0), 0)
        XCTAssertEqual(confidence(CompositionVelocityModel.stableBandPercent), 0)
        XCTAssertEqual(confidence(CompositionVelocityModel.confidentChangePercent), 1,
                       accuracy: 1e-9)
        XCTAssertEqual(confidence(5.0), 1, "and never exceeds 1 however fast")
        XCTAssertEqual(confidence(0.25), confidence(-0.25), accuracy: 1e-9,
                       "gaining at a rate is as confidently a change as losing at it")
        var previous = -1.0
        for step in stride(from: 0.0, through: 0.6, by: 0.02) {
            let value = confidence(step)
            XCTAssertGreaterThanOrEqual(value, previous, "ramp went backwards at \(step)")
            previous = value
        }
        XCTAssertEqual(previous, 1, accuracy: 1e-9, "and it does reach the top")
    }

    /// A body genuinely losing fast still gets the quality term at full weight
    /// — the ramp discounts marginal evidence, not the finding itself.
    func testARealChangeStillCountsInFull() throws {
        var out: [HealthMetricSample] = []
        for day in stride(from: 89, through: 0, by: -1) {
            let date = TestClock.utc.date(byAdding: .day, value: -day, to: TestClock.now)!
            // ~0.9 kg a week, comfortably a real loss.
            let weight = 110.5 - Double(89 - day) * 0.13 + Double(day % 4) * 0.4
            out.append(.init(type: .bodyMass, value: weight, start: date, source: .withings))
            out.append(.init(type: .leanBodyMass, value: weight * 0.68,
                             start: date, source: .withings))
        }
        let velocity = try XCTUnwrap(CompositionVelocityModel.evaluate(
            samples: out, now: TestClock.now, calendar: TestClock.utc))
        XCTAssertEqual(velocity.changeConfidence, 1, accuracy: 1e-9,
                       "a real loss must not be discounted: \(velocity.percentPerWeek) %/week")
    }

    /// Whether the scale reported a fat percentage that morning is not a change
    /// in the body, and must not read as one.
    func testAMissingFatReadingIsNotACrater() throws {
        let withFat = BodyCompositionInsight().evaluate(
            samples: samples(bodyFatOn: [0]), profile: profile, now: TestClock.now)
        let withoutFat = BodyCompositionInsight().evaluate(
            samples: samples(bodyFatOn: []), profile: profile, now: TestClock.now)
        let a = try XCTUnwrap(withFat.score)
        let b = try XCTUnwrap(withoutFat.score)
        XCTAssertLessThan(abs(a - b), 15,
            "same body, same weights, only the fat reading absent — scored \(a) vs \(b)")
    }
}
