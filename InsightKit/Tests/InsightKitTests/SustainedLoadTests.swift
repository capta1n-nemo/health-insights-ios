import XCTest
@testable import InsightKit

/// The reader asked for a stress card on 2026-08-03, and the roadmap note
/// written then named the only thing that could make it worth building:
///
/// > *"The risk is overlap — Readiness absorbed the vitals scan and the early
/// > warning for exactly this reason — so the honest version needs to answer a
/// > question Readiness does not, most likely **sustained** load rather than
/// > today."*
///
/// These pin that it answers the different question, and that it refuses the
/// two ways a card like this usually lies.
final class SustainedLoadTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// A history where the last `shiftedDays` sit at a different level.
    private func history(shiftedDays: Int, hrvShift: Double, rhrShift: Double,
                         respShift: Double = 0) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let jitter: [Double] = [0, 2, -1, 3, -2, 1, -3, 2, -1, 0, 1, -2]
        for day in 0..<130 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            let shifted = day < shiftedDays
            let n = jitter[day % jitter.count]
            func add(_ type: MetricType, _ value: Double) {
                out.append(HealthMetricSample(type: type, value: value,
                                              start: date, end: date, source: .oura))
            }
            add(.heartRateVariabilityRMSSD, 60 + n + (shifted ? hrvShift : 0))
            add(.restingHeartRate, 55 + n * 0.3 + (shifted ? rhrShift : 0))
            add(.respiratoryRate, 15 + n * 0.1 + (shifted ? respShift : 0))
            add(.sleepDurationHours, 7.5 + n * 0.05)
        }
        return out
    }

    /// **The card's reason to exist.** A month of every night sitting low is
    /// invisible to a detector asking "is today unusual", because by the second
    /// week it is not — but it is exactly what this window sees.
    func testASustainedShiftIsSeenWhereADailyCheckWouldNotSeeIt() throws {
        let settled = try XCTUnwrap(SustainedLoadModel.evaluate(
            samples: history(shiftedDays: 0, hrvShift: 0, rhrShift: 0),
            now: now, calendar: utc))
        let loaded = try XCTUnwrap(SustainedLoadModel.evaluate(
            samples: history(shiftedDays: 28, hrvShift: -12, rhrShift: 5, respShift: 1),
            now: now, calendar: utc))

        XCTAssertGreaterThan(settled.score, loaded.score,
                             "a month of raised load scored no worse than a settled month")
        XCTAssertGreaterThan(loaded.load, settled.load)
        XCTAssertEqual(SustainedLoadModel.band(loaded.score), "Running hot")
    }

    /// **A move the welcome way is not evidence of load**, and must not cancel
    /// out a channel that genuinely moved the wrong way.
    func testAWelcomeMoveNeverSubtractsFromLoad() throws {
        let raisedOnly = try XCTUnwrap(SustainedLoadModel.evaluate(
            samples: history(shiftedDays: 28, hrvShift: 0, rhrShift: 5),
            now: now, calendar: utc))
        // Same raised resting HR, plus a *better* HRV. The load must not fall.
        let raisedPlusGoodHRV = try XCTUnwrap(SustainedLoadModel.evaluate(
            samples: history(shiftedDays: 28, hrvShift: +15, rhrShift: 5),
            now: now, calendar: utc))
        XCTAssertEqual(raisedOnly.load, raisedPlusGoodHRV.load, accuracy: 0.001,
                       "an unusually good HRV cancelled a raised resting heart rate")
    }

    /// One channel drifting is one channel drifting. This card exists to say
    /// that several did, so it declines rather than reporting a single signal
    /// as a body under load.
    func testItDeclinesOnASingleChannel() {
        var thin: [HealthMetricSample] = []
        for day in 0..<130 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            thin.append(HealthMetricSample(type: .restingHeartRate,
                                           value: 55 + Double(day % 3),
                                           start: date, end: date, source: .oura))
        }
        XCTAssertNil(SustainedLoadModel.evaluate(samples: thin, now: now, calendar: utc))
    }

    /// Too little history says nothing rather than comparing a fortnight with
    /// itself.
    func testItDeclinesWithoutBothWindows() {
        let short = history(shiftedDays: 0, hrvShift: 0, rhrShift: 0)
            .filter { $0.start > now.addingTimeInterval(-20 * 86_400) }
        XCTAssertNil(SustainedLoadModel.evaluate(samples: short, now: now, calendar: utc))
    }

    /// The empty state must ask for the thing it needs, or the card is filtered
    /// off the tab and can never explain itself.
    func testTheEmptyStateAsksAndStaysOnScreen() {
        let result = SustainedLoadInsight().evaluate(samples: [], profile: .init(), now: now)
        XCTAssertTrue(result.isWorthShowing)
        XCTAssertTrue(result.invitesInput)
        XCTAssertNil(result.score)
    }

    /// **It must never imply a cause.** Four autonomic signals move for stress,
    /// illness, alcohol, heat and hard training alike, and this card cannot
    /// tell them apart — so it says so, every time it says anything.
    func testItNamesWhatItCannotTellApart() throws {
        let result = SustainedLoadInsight().evaluate(
            samples: history(shiftedDays: 28, hrvShift: -12, rhrShift: 5),
            profile: .init(), now: now)
        let text = result.drivers.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("cannot tell stress from illness"),
                      "the card asserted a cause it cannot see: \(text)")
    }

    /// The score is a curve, not a staircase — `verify.sh` bans the `switch`
    /// form because twenty points between two adjacent readings is a defect
    /// this repo has shipped seven times.
    func testTheScoreCurveHasNoCliffs() {
        var previous = SustainedLoadModel.score(load: 0)
        for step in 1...4000 {
            let value = SustainedLoadModel.score(load: Double(step) / 1000)
            XCTAssertLessThan(abs(value - previous), 1.0,
                              "a jump of more than a point at load \(Double(step) / 1000)")
            previous = value
        }
    }

    /// Higher is better, like every other dial in this app.
    func testHigherIsBetter() {
        XCTAssertGreaterThan(SustainedLoadModel.score(load: 0),
                             SustainedLoadModel.score(load: 2))
    }
}
