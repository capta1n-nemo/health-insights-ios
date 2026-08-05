import XCTest
@testable import InsightKit

/// **Nine clauses of equal weight is a list, not a summary.**
///
/// The reader, 2026-08-05: *"what you're doing very well and very poorly, and
/// any overall insights that are most important. like, hey! looks like you're
/// about to get sick."*
///
/// What they had enumerated every scored card in registry order and joined it
/// with commas, so the ranking the card exists to do was left to them. It also
/// read badly: `"\(title.lowercased()) is \(headline)"` assumes every headline
/// is a predicate, and several are values — *"body composition is Body fat
/// 30.6%"* was the reader's own example.
final class DailyHighlightsTests: XCTestCase {

    private func result(_ id: InsightID, _ title: String,
                        _ headline: String, _ score: Double) -> InsightResult {
        InsightResult(id: id, title: title, primaryValue: score, headline: headline,
                      score: score, confidence: .moderate, explanation: "x",
                      drivers: [], unmetRequirements: [])
    }

    /// The reader's actual panel on 2026-08-05, scores from their own export.
    private var realPanel: [InsightResult] {
        [result(.readiness, "Readiness", "Take it easy", 53),
         result(.symptomRadar, "Symptom radar", "Nothing stirring", 100),
         result(.sleep, "Sleep", "Poor", 49),
         result(.energy, "Energy", "85 · High", 85),
         result(.heartHealth, "Heart Health", "Fair", 60),
         result(.fitness, "Fitness", "Needs work", 47),
         result(.cardiovascularRisk, "Heart Attack & Stroke Risk", "0.7%", 99),
         result(.bloodPressure, "Blood Pressure", "144/88", 58),
         result(.bodyComposition, "Body Composition", "Body fat 30.6%", 55)]
    }

    // MARK: - Selection

    func testNineCardsBecomeAtMostThree() {
        XCTAssertLessThanOrEqual(DailyHighlights.highlights(from: realPanel).count, 3)
    }

    /// The whole point: the summary is a ranking, so the best and the weakest
    /// must both be in it.
    func testTheBestAndTheWeakestBothSurvive() {
        let ids = DailyHighlights.highlights(from: realPanel).map(\.id)
        XCTAssertTrue(ids.contains(.symptomRadar) || ids.contains(.cardiovascularRisk),
                      "neither of the two best-scoring cards is mentioned")
        XCTAssertTrue(ids.contains(.fitness),
                      "the weakest card — 47, the lowest on the panel — is not mentioned")
    }

    /// **The "about to get sick" slot.** A card the app is worried about leads,
    /// ahead of anything doing well.
    func testAPoorCardLeads() throws {
        var panel = realPanel
        panel.append(result(.substanceImpact, "Substance Impact", "Heavy fortnight", 22))
        let first = try XCTUnwrap(DailyHighlights.highlights(from: panel).first)
        XCTAssertEqual(first.id, .substanceImpact,
                       "a card in the poor band did not lead — the reader has to find it themselves")
        XCTAssertTrue(DailyHighlights.summary(from: panel).hasPrefix("Worth a look today"),
                      DailyHighlights.summary(from: panel))
    }

    /// Two red cards is the cap. A panel that is entirely red does not become a
    /// five-clause list of how bad everything is.
    func testAnEntirelyPoorPanelStillSaysAtMostThreeThings() {
        let grim = [result(.readiness, "Readiness", "Take it easy", 10),
                    result(.sleep, "Sleep", "Poor", 12),
                    result(.fitness, "Fitness", "Needs work", 14),
                    result(.heartHealth, "Heart Health", "Fair", 16),
                    result(.energy, "Energy", "Low", 18)]
        XCTAssertEqual(DailyHighlights.highlights(from: grim).count, 3)
    }

    /// No card twice, however the bands fall.
    func testNoCardIsMentionedTwice() {
        for panel in [realPanel, [result(.sleep, "Sleep", "Poor", 30)]] {
            let ids = DailyHighlights.highlights(from: panel).map(\.id)
            XCTAssertEqual(ids.count, Set(ids).count, "a card appears twice in one summary")
        }
    }

    /// A single scored card is a legitimate panel, not an edge case to crash on.
    func testASinglePoorCardIsMentionedOnce() {
        let one = [result(.sleep, "Sleep", "Poor", 30)]
        XCTAssertEqual(DailyHighlights.highlights(from: one).map(\.id), [.sleep])
    }

    func testNothingScoredGivesTheEmptyState() {
        XCTAssertEqual(DailyHighlights.summary(from: []), DailyHighlights.emptyState)
    }

    // MARK: - Phrasing

    /// **The reader's own complaint, asserted directly.** "is" cannot join a
    /// title to a headline that is a value.
    func testAValueHeadlineIsNeverJoinedWithIs() {
        let panel = [result(.bodyComposition, "Body Composition", "Body fat 30.6%", 20)]
        let text = DailyHighlights.summary(from: panel)
        XCTAssertFalse(text.lowercased().contains("body composition is body fat"),
                       "the phrasing the reader reported is back: \(text)")
        XCTAssertTrue(text.contains("Body fat 30.6%"),
                      "the figure was mangled by the lower-casing rule: \(text)")
    }

    /// A verdict headline reads better mid-clause in lower case; the rule keys
    /// on whether the headline carries a digit, and both halves are pinned.
    func testAVerdictIsLowerCasedAndAFigureIsNot() {
        let verdict = DailyHighlights.summary(from: [result(.fitness, "Fitness", "Needs work", 20)])
        XCTAssertTrue(verdict.contains("needs work"), verdict)

        let figure = DailyHighlights.summary(from: [result(.bloodPressure, "Blood Pressure", "144/88", 20)])
        XCTAssertTrue(figure.contains("144/88"), figure)
    }

    /// Every summary ends with the same invitation, and the score is stated so
    /// the sentence carries a number the reader can compare tomorrow.
    func testTheSummaryCarriesTheScoreAndTheInvitation() {
        let text = DailyHighlights.summary(from: realPanel)
        XCTAssertTrue(text.hasSuffix("Tap any card for what's driving it."), text)
        XCTAssertTrue(text.contains("out of 100"), text)
    }

    /// It must not read as a list of everything — the defect in one assertion.
    func testTheSummaryDoesNotEnumerateThePanel() {
        let text = DailyHighlights.summary(from: realPanel)
        let mentioned = realPanel.filter { text.contains($0.title) }
        XCTAssertLessThanOrEqual(mentioned.count, 3,
                                 "the summary is enumerating the panel again: \(text)")
    }

    /// **A detector is never "looking best".** The radar at 100 means nothing
    /// was detected, and the card itself says quiet is not an all-clear — the
    /// published validation catches 43% of confirmed illnesses. Opening the day
    /// with "looking best today: symptom radar" would contradict the card one
    /// tap away. Same ruling that took the radar off the comparison web.
    func testTheSymptomRadarIsNeverTheGoodNews() {
        let text = DailyHighlights.summary(from: realPanel)
        XCTAssertFalse(text.contains("Looking best today: Symptom radar"), text)
        XCTAssertFalse(text.contains("Doing well: Symptom radar"), text)
    }

    /// But it must still lead when it is *not* quiet — that is the state the
    /// reader asked to have surfaced ("looks like you're about to get sick").
    func testTheSymptomRadarStillLeadsWhenItIsNotQuiet() throws {
        var panel = realPanel.filter { $0.id != .symptomRadar }
        panel.append(result(.symptomRadar, "Symptom radar", "Strong signs", 30))
        let first = try XCTUnwrap(DailyHighlights.highlights(from: panel).first)
        XCTAssertEqual(first.id, .symptomRadar,
                       "the radar is picking something up and the summary buried it")
    }

    /// Three distinct things get said when three are available — the weakest
    /// must not be dropped just because it is also the card that led.
    func testThreeThingsAreSaidWhenThereAreThreeToSay() {
        var panel = realPanel
        panel.append(result(.substanceImpact, "Substance Impact", "Heavy fortnight", 22))
        let ids = DailyHighlights.highlights(from: panel).map(\.id)
        XCTAssertEqual(ids.count, 3, "a clause was lost to a duplicate pick")
        XCTAssertTrue(ids.contains(.fitness),
                      "the weakest scored card fell out when the lead was also the lowest")
    }

    // MARK: - Bands

    func testBandFloors() {
        XCTAssertEqual(ScoreBand(score: 100), .good)
        XCTAssertEqual(ScoreBand(score: 70), .good)
        XCTAssertEqual(ScoreBand(score: 69.9), .fair)
        XCTAssertEqual(ScoreBand(score: 45), .fair)
        XCTAssertEqual(ScoreBand(score: 44.9), .poor)
        XCTAssertEqual(ScoreBand(score: 0), .poor)
    }
}
