import XCTest
@testable import InsightKit

/// The gait triad was scraped into the raw pile from the first version of this
/// app and read by nothing for a year. Measured against the reader's own export
/// on 2026-08-05 it is the densest signal in the whole record — 1,093 days each,
/// 91 of the last 90 — and nothing else is close.
///
/// These pin the one thing this card can say that a number cannot, and the two
/// ways a card like this lies.
final class GaitTests: XCTestCase {

    private let utc = TestClock.utc
    private let now = TestClock.now

    /// A year and a bit of walking, where the last `shiftedDays` differ.
    ///
    /// `speedShift` and `lengthShift` are fractional — pass one without the
    /// other and cadence necessarily moved, which is exactly what the
    /// decomposition exists to detect.
    private func history(shiftedDays: Int, speedShift: Double = 0,
                         lengthShift: Double = 0,
                         doubleSupportShift: Double = 0) -> [HealthMetricSample] {
        var out: [HealthMetricSample] = []
        let jitter: [Double] = [0, 0.02, -0.01, 0.03, -0.02, 0.01, -0.03, 0.02, -0.01, 0]
        for day in 0..<200 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            let shifted = day < shiftedDays
            let n = jitter[day % jitter.count]
            func add(_ type: MetricType, _ value: Double) {
                out.append(HealthMetricSample(type: type, value: value,
                                              start: date, end: date, source: .appleHealth))
            }
            add(.walkingSpeed, 1.30 * (1 + n) * (shifted ? 1 + speedShift : 1))
            add(.walkingStepLength, 74 * (1 + n) * (shifted ? 1 + lengthShift : 1))
            add(.walkingDoubleSupport, 27 * (1 + n) * (shifted ? 1 + doubleSupportShift : 1))
            add(.walkingSteadiness, 85 * (1 + n))
            add(.walkingAsymmetry, 2 * (1 + n))
        }
        return out
    }

    // MARK: - The decomposition, which is the card's reason to exist

    /// **Speed is step length times cadence, exactly.** So a speed that fell
    /// entirely because the steps got shorter must be attributed to step length
    /// and not to rhythm — that is the sentence no competitor can print, because
    /// none of them holds step length.
    func testAShorterStepIsBlamedOnTheStepAndNotOnTheRhythm() throws {
        let out = try XCTUnwrap(GaitModel.evaluate(
            samples: history(shiftedDays: 28, speedShift: -0.06, lengthShift: -0.06),
            now: now, calendar: utc))
        let split = try XCTUnwrap(out.split)
        let share = try XCTUnwrap(split.stepLengthShare)

        XCTAssertGreaterThan(share, 0.9, "a purely step-length slowdown was blamed on cadence")
        XCTAssertEqual(split.cadenceChange, 0, accuracy: 0.01,
                       "cadence moved when only step length was changed")
    }

    /// The mirror image: same steps, taken less often.
    func testTheSameStepsTakenLessOftenIsBlamedOnTheRhythm() throws {
        let out = try XCTUnwrap(GaitModel.evaluate(
            samples: history(shiftedDays: 28, speedShift: -0.06, lengthShift: 0),
            now: now, calendar: utc))
        let split = try XCTUnwrap(out.split)
        let share = try XCTUnwrap(split.stepLengthShare)

        XCTAssertLessThan(share, 0.1, "a purely cadence slowdown was blamed on step length")
        XCTAssertLessThan(split.cadenceChange, -0.04)
    }

    /// ⚠️ **Dividing a rounding error into halves produces two confident-looking
    /// numbers about nothing.** Below half a percent the split declines rather
    /// than apportioning noise.
    func testATinyChangeIsNotApportioned() throws {
        let out = try XCTUnwrap(GaitModel.evaluate(
            samples: history(shiftedDays: 28, speedShift: 0.001, lengthShift: 0.001),
            now: now, calendar: utc))
        let split = try XCTUnwrap(out.split)
        XCTAssertNil(split.stepLengthShare,
                     "a 0.1% speed change was apportioned as though it meant something")
    }

    /// The two shares sum to the whole, which is the property that makes the log
    /// form worth using rather than a fit.
    func testTheTwoSharesAccountForTheWholeChange() throws {
        let out = try XCTUnwrap(GaitModel.evaluate(
            samples: history(shiftedDays: 28, speedShift: -0.08, lengthShift: -0.05),
            now: now, calendar: utc))
        let split = try XCTUnwrap(out.split)
        let reconstructed = (1 + split.stepLengthChange) * (1 + split.cadenceChange) - 1
        XCTAssertEqual(reconstructed, split.speedChange, accuracy: 0.002,
                       "step length times cadence did not reconstruct the speed change")
    }

    // MARK: - Scoring

    /// A month of walking the same way as the previous year scores better than a
    /// month of walking worse. The card's basic claim.
    func testAWorseMonthScoresWorse() throws {
        let steady = try XCTUnwrap(GaitModel.evaluate(samples: history(shiftedDays: 0),
                                                      now: now, calendar: utc))
        let declined = try XCTUnwrap(GaitModel.evaluate(
            samples: history(shiftedDays: 28, speedShift: -0.08, lengthShift: -0.06,
                             doubleSupportShift: 0.15),
            now: now, calendar: utc))
        XCTAssertGreaterThan(steady.score, declined.score)
        XCTAssertGreaterThan(declined.drift, steady.drift)
    }

    /// **Walking better than your own year is a fine thing and must not cancel a
    /// measure that moved the wrong way.** Same failure the symptom radar had,
    /// pinned here before it can happen again.
    func testAWelcomeMoveNeverSubtractsFromDrift() throws {
        let worseSupport = try XCTUnwrap(GaitModel.evaluate(
            samples: history(shiftedDays: 28, doubleSupportShift: 0.2),
            now: now, calendar: utc))
        let worseSupportButFaster = try XCTUnwrap(GaitModel.evaluate(
            samples: history(shiftedDays: 28, speedShift: 0.1, lengthShift: 0.1,
                             doubleSupportShift: 0.2),
            now: now, calendar: utc))
        XCTAssertEqual(worseSupport.drift, worseSupportButFaster.drift, accuracy: 0.02,
                       "an unusually fast month cancelled a gait spending longer on two feet")
    }

    func testTheScoreCurveHasNoCliffs() {
        var previous = GaitModel.score(drift: 0)
        for step in 1...4000 {
            let value = GaitModel.score(drift: Double(step) / 1000)
            XCTAssertLessThan(abs(value - previous), 1.0,
                              "a jump of more than a point at drift \(Double(step) / 1000)")
            previous = value
        }
    }

    func testHigherIsBetter() {
        XCTAssertGreaterThan(GaitModel.score(drift: 0), GaitModel.score(drift: 2))
    }

    // MARK: - What it refuses to say

    /// Too little history says nothing rather than comparing a fortnight with
    /// itself.
    func testItDeclinesWithoutBothWindows() {
        let short = history(shiftedDays: 0)
            .filter { $0.start > now.addingTimeInterval(-20 * 86_400) }
        XCTAssertNil(GaitModel.evaluate(samples: short, now: now, calendar: utc))
    }

    /// The empty state must ask for the thing it needs, or the card is filtered
    /// off the tab and can never explain itself.
    func testTheEmptyStateAsksAndStaysOnScreen() {
        let result = GaitInsight().evaluate(samples: [], profile: .init(), now: now)
        XCTAssertTrue(result.isWorthShowing)
        XCTAssertTrue(result.invitesInput)
        XCTAssertNil(result.score)
        XCTAssertTrue(result.explanation.lowercased().contains("no watch or ring"),
                      "the empty state did not say the thing that makes this card different")
    }

    /// ⚠️ **The caveat is the card.** A phone in a pocket sees the walking it was
    /// carried for, and a month of carrying it in a bag arrives here as *less*
    /// walking rather than *different* walking. Every rendering says so, because
    /// "your walking speed is falling" is heard as a sentence about ageing.
    func testItSaysThatItOnlySawWhatThePhoneSaw() {
        let result = GaitInsight().evaluate(
            samples: history(shiftedDays: 28, speedShift: -0.08, lengthShift: -0.06),
            profile: .init(), now: now)
        let text = result.drivers.joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("your phone was in your pocket for"),
                      "the card did not say whose walking it measured: \(text)")
        XCTAssertTrue(text.contains("your own previous year"),
                      "the card did not say what it compared against: \(text)")
    }

    /// ⚠️ **The famous thresholds do not apply here** — 0.8 m/s and 1.0 m/s come
    /// from supervised walks on a marked course, not from a pocket sensor's
    /// average, so drawing them would render a change in how the phone was
    /// carried as a clinical finding.
    func testNoPopulationBandIsDrawnOverAPocketSensor() {
        for metric: MetricType in [.walkingSpeed, .walkingStepLength, .walkingDoubleSupport] {
            XCTAssertNil(metric.referenceRange,
                         "\(metric) drew a population band over a phone-in-pocket average")
        }
    }
}
