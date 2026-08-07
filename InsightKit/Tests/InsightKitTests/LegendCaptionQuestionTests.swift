import XCTest
@testable import InsightKit

/// Backlog D45 — **two true statements that read as a contradiction.**
///
/// On Work impact, Sleep Duration's legend said "Holding steady · higher is
/// better · 22% of this score" while the card's own driver line said sleep was
/// about the same on the reader's busier working days — 6.7 against 7.4, which
/// is 0.2 SD worse. One is a trend across the chart window; the other is a
/// busy-versus-quiet contrast. Adjacent, with neither naming its question, they
/// read as the card arguing with itself.
///
/// Ruled 2026-08-07: the chip names its question — generally, in the caption,
/// so it holds for every contrast card rather than for the one screen.
final class LegendCaptionQuestionTests: XCTestCase {

    private let steady = PatternFinder.minimumSlope * 0.5
    private let rising = PatternFinder.minimumSlope * 4

    /// The reader's own row, as it now reads.
    func testTheSteadyChipNamesTheWindowItIsSteadyOver() {
        let caption = LegendCaption.series(trendPerWeek: steady, higherIsBetter: true,
                                           weight: 0.22, over: Timeframe.month.trendLabel)
        XCTAssertEqual(caption.direction, "30-day trend: holding steady")
        XCTAssertEqual(caption.text,
                       "30-day trend: holding steady · higher is better here · 22% of this score")
    }

    /// Every state carries the window, not only the steady one — a moving
    /// signal beside a contrast is the same collision.
    func testEveryDirectionStateNamesTheWindow() {
        for slope: Double? in [rising, -rising, steady, nil] {
            let caption = LegendCaption.series(trendPerWeek: slope, higherIsBetter: true,
                                               weight: 0.1, over: Timeframe.year.trendLabel)
            XCTAssertTrue(caption.direction.hasPrefix("12-month trend: "),
                          "unqualified direction: \(caption.direction)")
        }
    }

    /// "Too few days" is *most* in need of the window: how few is a property of
    /// the window, and a week and a year are two different statements.
    func testTooFewDaysSaysTooFewForWhat() {
        XCTAssertEqual(
            LegendCaption.series(trendPerWeek: nil, higherIsBetter: nil,
                                 weight: 0, over: Timeframe.week.trendLabel).direction,
            "7-day trend: too few days to call a direction")
    }

    /// A stand-in row carries the direction and nothing else, so an unqualified
    /// trend there has nothing beside it to say what it is a trend of.
    func testTheUnreportedRowNamesItsWindowToo() {
        XCTAssertEqual(
            LegendCaption.unreported(trendPerWeek: rising,
                                     over: Timeframe.sixMonths.trendLabel).direction,
            "6-month trend: trending up")
    }

    /// Naming the question must not change the judgement or the weighting — the
    /// other two answers are about the metric, not about the window.
    func testOnlyTheDirectionChanges() {
        let bare = LegendCaption.series(trendPerWeek: rising, higherIsBetter: false, weight: 0.4)
        let named = LegendCaption.series(trendPerWeek: rising, higherIsBetter: false,
                                         weight: 0.4, over: Timeframe.month.trendLabel)
        XCTAssertEqual(bare.judgement, named.judgement)
        XCTAssertEqual(bare.weighting, named.weighting)
        XCTAssertNotEqual(bare.direction, named.direction)
    }

    /// Omitting the window leaves the phrase exactly as it was, so a surface
    /// with no competing question is unchanged.
    func testNoWindowLeavesThePhraseAlone() {
        XCTAssertEqual(
            LegendCaption.series(trendPerWeek: steady, higherIsBetter: true, weight: 0.2).direction,
            "Holding steady")
    }

    /// Every timeframe has to produce a label a sentence can carry, and
    /// all-time is a window with no length — it must not print one.
    func testEveryTimeframeNamesItselfAndAllTimeClaimsNoLength() {
        for timeframe in Timeframe.allCases {
            XCTAssertTrue(timeframe.trendLabel.hasSuffix(" trend"),
                          "\(timeframe) → \(timeframe.trendLabel)")
        }
        XCTAssertEqual(Timeframe.all.trendLabel, "All-time trend")
    }

    /// Sentence case for the continuation, without flattening anything that is
    /// uppercase on purpose.
    func testContinuingLowercasesOnlyTheLeadingCapital() {
        XCTAssertEqual(LegendCaption.continuing("Trending up"), "trending up")
        XCTAssertEqual(LegendCaption.continuing("HRV is up"), "HRV is up")
        XCTAssertEqual(LegendCaption.continuing("already lower"), "already lower")
        XCTAssertEqual(LegendCaption.continuing(""), "")
    }
}
