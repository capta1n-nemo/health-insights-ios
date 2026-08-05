import XCTest
@testable import InsightKit

/// The reader, 2026-08-05: they cannot read the Today curve, and asked for
/// "How does this work?" and "So what?".
final class EnergyCurveExplainerTests: XCTestCase {

    private func output(sleep: Double? = 7.5, recoveryZ: Double? = 0.2,
                        morning: Double = 96, level: Double = 40, spent: Double = 56,
                        activeEnergy: Double? = 420,
                        exertion: Double? = 1.4) -> EnergyModel.Output {
        EnergyModel.Output(morningCharge: morning, level: level,
                           curve: [], spent: spent, sleepHours: sleep,
                           recoveryZ: recoveryZ, activeEnergy: activeEnergy,
                           exertionHours: exertion,
                           hrvMetric: .heartRateVariabilityRMSSD)
    }

    /// **The unit is not a real quantity, and the text has to say so.** Calling
    /// a 0–100 model "energy" without that invites a comparison with a calorie
    /// figure it has no relationship to.
    func testItSaysTheUnitIsNotCalories() throws {
        let text = try XCTUnwrap(EnergyCurveExplainer.howItWorks(output()))
        XCTAssertTrue(text.contains("not calories"), text)
        XCTAssertTrue(text.contains("0–100"), text)
    }

    /// The morning figure is the part the chart cannot show, because it was set
    /// before the first point.
    func testItExplainsWhereTheMorningChargeCameFrom() throws {
        let text = try XCTUnwrap(EnergyCurveExplainer.howItWorks(output()))
        XCTAssertTrue(text.contains("7.5 h"), text)
        XCTAssertTrue(text.contains("96"), text)
    }

    /// With neither input there is nothing honest to say, so it says nothing
    /// rather than describing a mechanism that did not run.
    func testNoInputsMeansNoExplanation() {
        XCTAssertNil(EnergyCurveExplainer.howItWorks(
            output(sleep: nil, recoveryZ: nil)))
    }

    func testRecoveryIsDescribedAgainstTheReadersOwnUsual() throws {
        let low = try XCTUnwrap(EnergyCurveExplainer.howItWorks(output(recoveryZ: -1.5)))
        let mid = try XCTUnwrap(EnergyCurveExplainer.howItWorks(output(recoveryZ: 0)))
        let high = try XCTUnwrap(EnergyCurveExplainer.howItWorks(output(recoveryZ: 1.5)))
        XCTAssertTrue(low.contains("below your usual"), low)
        XCTAssertTrue(mid.contains("about your usual"), mid)
        XCTAssertTrue(high.contains("above your usual"), high)
    }

    /// **No advice.** Describing the shape of a day is not prescribing one, and
    /// this card must never tell someone to stop or to push on.
    func testItNeverGivesAdvice() {
        let texts = [EnergyCurveExplainer.soWhat(output()),
                     EnergyCurveExplainer.howItWorks(output()) ?? ""]
        for text in texts {
            // Phrases, not bare words: the copy legitimately says "Nothing
            // here is a target", which is the disclaimer rather than the sin.
            for phrase in ["you should", "try to", "aim for", "make sure", "you need to",
                           "take it easy", "rest now", "your target"] {
                XCTAssertFalse(text.lowercased().contains(phrase),
                               "the energy card gave advice (\"\(phrase)\"): \(text)")
            }
        }
    }

    /// Same guard as the metric explainer: `Text` renders a String verbatim, and
    /// literal asterisks reached the HRV card earlier the same day.
    func testNoMarkdownReachesTheScreen() {
        for text in [EnergyCurveExplainer.soWhat(output()),
                     EnergyCurveExplainer.howItWorks(output()) ?? ""] {
            XCTAssertFalse(text.contains("**"), text)
            XCTAssertFalse(text.contains("`"), text)
            // Single asterisks too — `*shape*` slipped past a `**`-only check.
            XCTAssertFalse(text.contains("*"), text)
        }
    }

    /// The so-what quotes the reader's own day, and survives a day with no
    /// exertion recorded rather than printing a bare zero.
    func testSoWhatQuotesTheDayAndSurvivesAThinOne() {
        let full = EnergyCurveExplainer.soWhat(output())
        XCTAssertTrue(full.contains("420 kcal"), full)
        XCTAssertTrue(full.contains("56"), full)

        let thin = EnergyCurveExplainer.soWhat(output(activeEnergy: nil, exertion: nil))
        XCTAssertFalse(thin.contains("kcal"), "a day with no active energy still claimed one: \(thin)")
        XCTAssertTrue(thin.contains("shape"), thin)
    }

    /// A day that has overrun its charge reports nothing left rather than a
    /// negative reservoir.
    func testANegativeLevelReadsAsNothingLeft() {
        let text = EnergyCurveExplainer.soWhat(output(level: -12, spent: 108))
        XCTAssertTrue(text.contains("0 is left"), text)
        XCTAssertFalse(text.contains("-12"), text)
    }
}
