import XCTest
@testable import InsightKit

/// The legend line is three independent claims about the user's health, and
/// each of them can be *wrong* rather than merely absent — "trending up · the
/// good direction" against a metric where rising is the bad direction is a false
/// statement, and the app target has no test target to catch it.
///
/// What these pin is the defect the old row actually shipped: it printed one of
/// the three, chosen by an `if`, so which fact was missing varied row by row.
final class LegendCaptionTests: XCTestCase {

    /// Every caption a card can produce, for the sweeps.
    private var all: [LegendCaption] {
        var built: [LegendCaption] = [.unreportedAndUnrecorded]
        for slope: Double? in [nil, 0.0, 0.01, -0.01, 0.4, -0.4] {
            built.append(.unreported(trendPerWeek: slope))
            for better: Bool? in [nil, true, false] {
                for weight in [0.0, 0.0001, 0.24, 1.0] {
                    built.append(.series(trendPerWeek: slope, higherIsBetter: better,
                                         weight: weight))
                    built.append(.noReadings(higherIsBetter: better, weight: weight))
                }
            }
        }
        return built
    }

    // MARK: - The defect: one of three, chosen by an if

    /// The whole point. No combination of inputs may drop a part.
    func testEveryCaptionStatesAllThree() {
        for caption in all {
            XCTAssertFalse(caption.direction.isEmpty, "no direction: \(caption)")
            XCTAssertFalse(caption.judgement.isEmpty, "no judgement: \(caption)")
            XCTAssertFalse(caption.weighting.isEmpty, "no weighting: \(caption)")
            XCTAssertEqual(caption.text.components(separatedBy: " · ").count, 3,
                           "not three parts: \(caption.text)")
        }
    }

    /// A weighted signal used to say only its weight, so a signal carrying a
    /// quarter of the score never said which way it was going.
    func testAWeightedSignalStillStatesItsDirection() {
        let caption = LegendCaption.series(trendPerWeek: 0.4, higherIsBetter: true,
                                           weight: 0.24)
        XCTAssertEqual(caption.direction, "Trending up")
        XCTAssertEqual(caption.judgement, "the good direction")
        XCTAssertEqual(caption.weighting, "24% of this score")
    }

    /// And an unweighted one used to say only its direction, so "this isn't in
    /// the score" was never said out loud on the card where it mattered most.
    func testAnUnweightedSignalSaysSoRatherThanGoingSilent() {
        let caption = LegendCaption.series(trendPerWeek: -0.4, higherIsBetter: true,
                                           weight: 0)
        XCTAssertEqual(caption.weighting, "tracked, not scored")
        XCTAssertEqual(caption.judgement, "the direction to watch")
    }

    // MARK: - The judgement, which is the part that can be false

    /// Rising HRV and rising resting heart rate mean opposite things. A bare
    /// arrow implies otherwise, which is why the judgement exists at all.
    func testTheVerdictFollowsTheMetricsOwnGoodDirection() {
        XCTAssertEqual(LegendCaption.verdict(rising: true, higherIsBetter: true),
                       "the good direction")
        XCTAssertEqual(LegendCaption.verdict(rising: true, higherIsBetter: false),
                       "the direction to watch")
        XCTAssertEqual(LegendCaption.verdict(rising: false, higherIsBetter: true),
                       "the direction to watch")
        XCTAssertEqual(LegendCaption.verdict(rising: false, higherIsBetter: false),
                       "the good direction")
    }

    /// `nil` is a positive claim — a temperature deviation is best near zero —
    /// and must never be rendered as a verdict either way.
    func testNeitherDirectionIsNeverRenderedAsAVerdict() {
        for slope in [0.4, -0.4] {
            let caption = LegendCaption.series(trendPerWeek: slope, higherIsBetter: nil,
                                               weight: 0.1)
            XCTAssertEqual(caption.judgement, "neither direction is better")
            XCTAssertFalse(caption.text.contains("good direction"))
            XCTAssertFalse(caption.text.contains("to watch"))
        }
    }

    /// With nothing moving there is no verdict to give, but "is up good here"
    /// still has an answer and the reader still wants it.
    func testASteadySignalStatesWhichDirectionWouldBeBetter() {
        XCTAssertEqual(LegendCaption.series(trendPerWeek: 0, higherIsBetter: true,
                                            weight: 0.1).judgement,
                       "higher is better here")
        XCTAssertEqual(LegendCaption.series(trendPerWeek: 0, higherIsBetter: false,
                                            weight: 0.1).judgement,
                       "lower is better here")
    }

    // MARK: - Direction

    /// Below the slope floor is "steady", not "up by a hair". Same threshold
    /// `PatternFinder` gates a divergence on, so the legend and the patterns
    /// section cannot disagree about whether something is moving.
    func testTheSlopeFloorIsPatternFindersOwn() {
        let under = PatternFinder.minimumSlope * 0.99
        XCTAssertEqual(LegendCaption.series(trendPerWeek: under, higherIsBetter: true,
                                            weight: 0).direction,
                       "Holding steady")
        XCTAssertEqual(LegendCaption.series(trendPerWeek: PatternFinder.minimumSlope,
                                            higherIsBetter: true, weight: 0).direction,
                       "Trending up")
    }

    /// A series too short to fit a line through is not a flat one, and saying
    /// "steady" there would be an invented reassurance.
    func testTooShortToFitIsNotReportedAsSteady() {
        let caption = LegendCaption.series(trendPerWeek: nil, higherIsBetter: true,
                                           weight: 0.3)
        XCTAssertEqual(caption.direction, "Too few days to call a direction")
        XCTAssertNotEqual(caption.direction, "Holding steady")
    }

    // MARK: - The weight

    /// A weight that rounds to zero beside a signal that genuinely counts is the
    /// one reading of this line that is flatly untrue.
    func testATinyWeightNeverPrintsAsZeroPercent() {
        let caption = LegendCaption.series(trendPerWeek: 0.4, higherIsBetter: true,
                                           weight: 0.001)
        XCTAssertEqual(caption.weighting, "under 1% of this score")
        for one in all {
            XCTAssertFalse(one.weighting.hasPrefix("0%"), "printed 0%: \(one.weighting)")
        }
    }

    /// A declared input with no readings still has a weight and still has a
    /// preferred direction. The old "No data" row dropped both.
    func testAMissingSignalStillStatesItsWeightAndItsGoodDirection() {
        let caption = LegendCaption.noReadings(higherIsBetter: false, weight: 0.12)
        XCTAssertEqual(caption.direction, "No readings in this window")
        XCTAssertEqual(caption.judgement, "lower is better here")
        // Qualified: it is 12% of the score on the days it is recorded, and this
        // window has none of those days.
        XCTAssertEqual(caption.weighting, "12% of this score when recorded")
    }

    // MARK: - The stand-in, which is the same zeroes meaning something else

    /// A model that reported nothing has not decided that nothing matters. The
    /// stand-in's `weight: 0` and `higherIsBetter: nil` are absences, and
    /// running them through `series(...)` would print two findings — "tracked,
    /// not scored" and "neither direction is better" — on every row of a card
    /// whose model never said either. Substance Impact before its first logged
    /// event is the live case.
    func testAStandInReportsItsMeasuredDirectionAndClaimsNothingElse() {
        let standIn = LegendCaption.unreported(trendPerWeek: 0.4)
        let reported = LegendCaption.series(trendPerWeek: 0.4, higherIsBetter: nil,
                                            weight: 0)

        // The direction was measured either way, so it is stated either way.
        XCTAssertEqual(standIn.direction, reported.direction)
        XCTAssertEqual(standIn.direction, "Trending up")

        // The other two are absences, and must not read as the findings that
        // happen to share their encoding.
        XCTAssertEqual(standIn.judgement, "no preferred direction reported")
        XCTAssertEqual(standIn.weighting, "no weighting reported")
        XCTAssertNotEqual(standIn.judgement, reported.judgement)
        XCTAssertNotEqual(standIn.weighting, reported.weighting)
    }

    /// The absence of a claim and the claim that neither end is good are
    /// different statements, and a reader has to be able to tell them apart.
    func testAnUnknownPreferenceNeverBorrowsTheWordsForNeitherDirection() {
        XCTAssertNotEqual(LegendCaption.unknownPreference, LegendCaption.neitherDirection)
        XCTAssertFalse(LegendCaption.unreported(trendPerWeek: 0)
            .text.contains(LegendCaption.neitherDirection))
    }

    /// A stand-in with nothing recorded either — the row most likely to be read
    /// as a rendering fault if any part of it went blank.
    func testAStandInWithNoReadingsStillFillsAllThreeSlots() {
        let both = LegendCaption.unreportedAndUnrecorded
        XCTAssertEqual(both.direction, "No readings in this window")
        XCTAssertEqual(both.judgement, "no preferred direction reported")
        XCTAssertEqual(both.weighting, "no weighting reported")
    }

    // MARK: - Shape

    /// Sentence case, no full stop: this sits under a metric name as a label,
    /// not as prose, and a trailing stop before a middle dot reads as a typo.
    func testCaptionsReadAsALabelRatherThanASentence() {
        for caption in all {
            XCTAssertFalse(caption.text.hasSuffix("."), caption.text)
            XCTAssertEqual(caption.direction.first?.isUppercase, true, caption.text)
            XCTAssertEqual(caption.judgement.first?.isLowercase, true, caption.text)
            XCTAssertEqual(caption.weighting.first?.isUppercase, false, caption.text)
        }
    }
}
