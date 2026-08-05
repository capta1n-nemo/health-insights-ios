import XCTest
@testable import InsightKit

/// **The longer something persists, the more normal it looks** — the worst
/// failure available to a health warning, and the reader hit it twice in two
/// days on two different cards.
///
/// 2026-08-05, on "How far from your normal": *"Yesterday my HRV was in danger
/// zone, and today, its still the same value.. but no longer in danger? how is
/// that possible? its still super low"*.
///
/// And on the symptom radar the same morning: *"my heart rate is still
/// elevated, my HRV is still down… why am I now back at 99% just 1 day later?"*
///
/// One mechanism behind both. "Your normal" is a rolling window that had just
/// absorbed yesterday's reading; a z-score divides by the spread; a standard
/// deviation has a **breakdown point of zero**, so one excursion inflates it
/// without limit. The same value scores a smaller z and falls back under the
/// threshold without moving.
final class PersistentDepartureTests: XCTestCase {

    /// Twenty-eight settled days, then a sustained drop. Each successive low day
    /// enters the window that judges the next one.
    /// Real night-to-night variation, not an alternating pair: a fixture whose
    /// MAD is near zero makes every z enormous and proves nothing about decay.
    private func window(settled: Double, low: Double, lowDays: Int) -> [Double] {
        let jitter: [Double] = [0, 3, -2, 5, -4, 1, -3, 4, -1, 2, -5, 3, -2, 0]
        var out = (0..<28).map { settled + jitter[$0 % jitter.count] }
        out.append(contentsOf: Array(repeating: low, count: lowDays))
        return out
    }

    /// **The reader's case, asserted directly.** A value that was unusual on its
    /// first day must still be unusual on its fourth, with the intervening days
    /// inside the window.
    func testADepartureStaysADepartureAsItAgesIntoItsOwnBaseline() throws {
        var scores: [Double] = []
        for lowDays in 0..<4 {
            let history = window(settled: 60, low: 30, lowDays: lowDays)
            let z = try XCTUnwrap(Baseline.deviation(latest: 30, history: history,
                                                     robust: true)?.zScore)
            scores.append(abs(z))
        }
        // Not merely "still flagged" — it must stop decaying. The classical
        // spread shrinks the z on *every* additional low day; the robust one
        // settles after the first and holds.
        XCTAssertGreaterThan(scores.last!, VitalSignsCheck.unusualZ,
                             "after four days the same low value stopped reading as unusual: \(scores)")
        XCTAssertEqual(scores[1], scores[3], accuracy: 0.01,
                       "the departure is still shrinking as it persists: \(scores)")
    }

    /// The classical spread is what the reader was seeing, kept as the contrast
    /// so the fix cannot be quietly reverted without this failing.
    func testTheClassicalSpreadIsWhatDecayed() throws {
        let day1 = try XCTUnwrap(Baseline.deviation(latest: 30,
                                                    history: window(settled: 60, low: 30, lowDays: 0))?.zScore)
        let day4 = try XCTUnwrap(Baseline.deviation(latest: 30,
                                                    history: window(settled: 60, low: 30, lowDays: 3))?.zScore)
        XCTAssertLessThan(abs(day4), abs(day1) * 0.5,
                          "this fixture no longer reproduces the decay, so it proves nothing about the fix")
    }

    /// ⚠️ **Robustness is opt-in, and this is why.** On a steady linear
    /// improvement the robust spread approaches its asymptote differently, which
    /// showed up as `ReadinessScore` *falling* across a month of improving HRV.
    /// A reader getting better must never be told they are getting worse, so
    /// scoring keeps the classical estimator and only flagging goes robust.
    func testScoringKeepsTheClassicalEstimatorByDefault() throws {
        let history = (0..<28).map { 40.0 + Double($0) }
        let classical = try XCTUnwrap(Baseline.deviation(latest: 68, history: history)?.zScore)
        let robust = try XCTUnwrap(Baseline.deviation(latest: 68, history: history,
                                                      robust: true)?.zScore)
        XCTAssertNotEqual(classical, robust, accuracy: 0.0001,
                          "the two estimators agree here, so the default is untested")
    }

    /// **A flat window has no spread, so there is no z — and nil is the honest
    /// answer, not infinity.** MAD is zero and the classical fallback's SD is
    /// zero too, so both paths decline. The point of the test is that it
    /// declines the same way the classical path always has, rather than
    /// dividing by zero.
    func testAFlatWindowDeclinesRatherThanExploding() {
        let flat = Array(repeating: 60.0, count: 28)
        XCTAssertNil(Baseline.robustZScore(65, history: flat))
        XCTAssertNil(Baseline.zScore(65, history: flat), "the two must decline together")
    }

    /// A *majority*-identical window is the realistic version: MAD is exactly
    /// zero while the SD is not, so the fallback is what answers.
    func testAMajorityIdenticalWindowUsesTheFallback() throws {
        let majority = Array(repeating: 60.0, count: 20) + [55, 58, 62, 65, 57, 63, 59, 61]
        let z = try XCTUnwrap(Baseline.robustZScore(40, history: majority))
        XCTAssertTrue(z.isFinite && z < 0, "the fallback produced no usable answer: \(z)")
    }
}
