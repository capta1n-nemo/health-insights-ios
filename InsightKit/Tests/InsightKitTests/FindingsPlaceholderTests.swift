import XCTest
@testable import InsightKit

private let placeholderCalendar = TestClock.utc

/// "Patterns worth a look" and "What comes first" now render on every card,
/// including the cards where the finder returns nothing — which is most of them,
/// most of the time. What they render instead is a claim about the user's data,
/// and the wrong claim is worse than the empty section it replaced: "not yet
/// enough data" under a card holding two years of it is a lie the reader has no
/// way to check.
///
/// So each of these pins one reason against a dataset that has exactly that
/// shape, and the sweeps pin that the three reasons never blur into each other.
final class FindingsPlaceholderTests: XCTestCase {

    // MARK: - Fixtures

    private func series(_ metric: MetricType, days: Int,
                        from offset: Int = 0,
                        higherIsBetter: Bool? = true,
                        step: Double = 0) -> NormalizedSeries {
        let values = (0..<days).map { 10.0 + Double($0) * step + Double($0 % 3) }
        let mean = Baseline.mean(values) ?? 0
        let sd = Baseline.standardDeviation(values) ?? 1
        let points = values.enumerated().map { index, value in
            NormalizedPoint(date: TestClock.day(offset + days - 1 - index),
                            z: sd == 0 ? 0 : (value - mean) / sd, raw: value)
        }
        return NormalizedSeries(metric: metric, higherIsBetter: higherIsBetter,
                                points: points, baseline: mean)
    }

    private func score(days: Int) -> [ScorePoint] {
        (0..<days).map { index in
            ScorePoint(date: TestClock.day(days - 1 - index),
                       score: 60 + Double(index % 5),
                       confidence: .moderate, contributorCount: 3)
        }
    }

    /// Every reason "Patterns worth a look" can give, one dataset each.
    private var patternReasons: [FindingsPlaceholder] {
        [
            .patterns(series: [], score: [], calendar: placeholderCalendar),
            .patterns(series: [series(.sleepDurationHours, days: 30)], score: [],
                      calendar: placeholderCalendar),
            .patterns(series: [series(.sleepDurationHours, days: 4),
                               series(.oxygenSaturation, days: 4)],
                      score: [], calendar: placeholderCalendar),
            .patterns(series: [series(.sleepDurationHours, days: 30),
                               series(.oxygenSaturation, days: 30)],
                      score: [], calendar: placeholderCalendar)
        ]
    }

    /// And every reason "What comes first" can give.
    private var leadReasons: [FindingsPlaceholder] {
        let two = [series(.sleepDurationHours, days: 30),
                   series(.oxygenSaturation, days: 30)]
        return [
            .leads(series: [], score: [], calendar: placeholderCalendar),
            .leads(series: two, score: score(days: 3), calendar: placeholderCalendar),
            .leads(series: [series(.sleepDurationHours, days: 3)], score: score(days: 40),
                   calendar: placeholderCalendar),
            .leads(series: two, score: score(days: 40), calendar: placeholderCalendar)
        ]
    }

    private var everyPlaceholder: [FindingsPlaceholder] { patternReasons + leadReasons }

    // MARK: - Patterns: the three reasons are not interchangeable

    func testNoSeriesSaysNothingIsRecordingRatherThanNothingIsWrong() {
        let empty = FindingsPlaceholder.patterns(series: [], score: [],
                                                 calendar: placeholderCalendar)
        XCTAssertEqual(empty, FindingsPlaceholder.nothingRecording)
        XCTAssertTrue(empty.headline.lowercased().contains("nothing recording"))
        // Must not read as reassurance: no data is not the same as no problem.
        XCTAssertFalse(empty.detail.lowercased().contains("ordinary state"))
    }

    /// A card drawing one signal with no score history has no *pair*, which is a
    /// different answer from "we looked and found nothing".
    func testOneSignalAndNoScoreSaysThereIsNothingToCompareItWith() {
        let one = FindingsPlaceholder.patterns(
            series: [series(.sleepDurationHours, days: 40)], score: [],
            calendar: placeholderCalendar)
        XCTAssertTrue(one.headline.lowercased().contains("one signal"), one.headline)
    }

    /// Two readings of one measurement are not a pair — the same guard
    /// `PatternFinder` applies, so the placeholder cannot claim a pair the
    /// finder would have refused to look at.
    func testTwoReadingsOfOneMeasurementDoNotCountAsAPair() {
        let sameBasis = FindingsPlaceholder.patterns(
            series: [series(.heartRateVariabilityRMSSD, days: 40),
                     series(.heartRateVariabilitySDNN, days: 40)],
            score: [], calendar: placeholderCalendar)
        XCTAssertTrue(sameBasis.headline.lowercased().contains("one signal"),
                      sameBasis.headline)
    }

    /// The defect this whole type exists to avoid: telling a reader nothing
    /// stood out when in truth nothing was looked at.
    func testAShortOverlapIsReportedAsAShortOverlapAndQuotesIt() {
        let short = FindingsPlaceholder.patterns(
            series: [series(.sleepDurationHours, days: 5),
                     series(.oxygenSaturation, days: 5)],
            score: [], calendar: placeholderCalendar)
        XCTAssertTrue(short.headline.lowercased().contains("not enough overlapping"),
                      short.headline)
        XCTAssertTrue(short.detail.contains("5 days"), short.detail)
        XCTAssertTrue(short.detail.contains("\(PatternFinder.defaultMinimumPairs) days"),
                      short.detail)
        XCTAssertFalse(short.detail.lowercased().contains("ordinary state"))
    }

    /// One day of overlap must not read "1 days" — the plural bug this repo has
    /// already shipped once.
    func testTheOverlapCountIsWordedForItsOwnNumber() {
        let one = FindingsPlaceholder.patterns(
            series: [series(.sleepDurationHours, days: 1),
                     series(.oxygenSaturation, days: 1)],
            score: [], calendar: placeholderCalendar)
        XCTAssertTrue(one.detail.contains("1 day."), one.detail)
        XCTAssertFalse(one.detail.contains("1 days"), one.detail)
    }

    /// And the reassuring case, which the vanishing section never gave anyone:
    /// enough days, nothing moving together, and that is fine.
    func testEnoughDaysWithNothingMovingTogetherSaysSoOutLoud() {
        let plenty = FindingsPlaceholder.patterns(
            series: [series(.sleepDurationHours, days: 40),
                     series(.oxygenSaturation, days: 40)],
            score: [], calendar: placeholderCalendar)
        XCTAssertTrue(plenty.headline.lowercased().contains("nothing worth flagging"),
                      plenty.headline)
        XCTAssertTrue(plenty.detail.contains("0.3"), plenty.detail)
        // The floor is quoted, not spelled out to a float's full expansion.
        XCTAssertFalse(plenty.detail.contains("0.30000"), plenty.detail)
    }

    // MARK: - What comes first

    func testAShortScoreHistoryIsNamedAsTheBlockerAndQuotesTheCount() {
        let short = FindingsPlaceholder.leads(
            series: [series(.sleepDurationHours, days: 40)], score: score(days: 6),
            calendar: placeholderCalendar)
        XCTAssertTrue(short.headline.lowercased().contains("score history"), short.headline)
        XCTAssertTrue(short.detail.contains("are 6"), short.detail)
        XCTAssertTrue(short.detail.contains("\(PatternFinder.defaultMinimumPairs) days"),
                      short.detail)
    }

    func testOneDayOfScoreHistoryReadsAsSingular() {
        let one = FindingsPlaceholder.leads(
            series: [series(.sleepDurationHours, days: 40)], score: score(days: 1),
            calendar: placeholderCalendar)
        XCTAssertTrue(one.detail.contains("is 1 so far"), one.detail)
    }

    /// Plenty of score history but a signal recorded on almost none of those
    /// days is a *third* reason, and blaming the score history would send the
    /// reader to wait for something they already have.
    func testALongScoreHistoryWithASparseSignalBlamesTheOverlapNotTheHistory() {
        let sparse = FindingsPlaceholder.leads(
            series: [series(.sleepDurationHours, days: 4)], score: score(days: 40),
            calendar: placeholderCalendar)
        XCTAssertTrue(sparse.headline.lowercased().contains("overlapping"), sparse.headline)
        XCTAssertTrue(sparse.detail.contains("40 days behind it"), sparse.detail)
        XCTAssertTrue(sparse.detail.contains("at most 4"), sparse.detail)
    }

    func testEnoughOfEverythingAndNoLeadSaysThatIsTheUsualAnswer() {
        let plenty = FindingsPlaceholder.leads(
            series: [series(.sleepDurationHours, days: 40)], score: score(days: 40),
            calendar: placeholderCalendar)
        XCTAssertTrue(plenty.headline.lowercased().contains("ahead of your score"),
                      plenty.headline)
        XCTAssertTrue(plenty.detail.lowercased().contains("usual answer"), plenty.detail)
    }

    // MARK: - Shape, across every reason

    /// The headline is what a collapsed section shows, so for most readers it is
    /// the whole section. It has to fit one line and stand up alone.
    func testHeadlinesAreOneShortLineWithNoFullStop() {
        for placeholder in everyPlaceholder {
            XCTAssertFalse(placeholder.headline.isEmpty)
            XCTAssertLessThanOrEqual(placeholder.headline.count, 44, placeholder.headline)
            XCTAssertFalse(placeholder.headline.hasSuffix("."), placeholder.headline)
            XCTAssertEqual(placeholder.headline.first?.isUppercase, true,
                           placeholder.headline)
        }
    }

    /// Every reason says what is being waited for. "Check back later" with no
    /// stated condition is the failure mode of an empty state.
    func testEveryDetailSaysWhatWouldChangeTheAnswer() {
        let escapes = ["keep recording", "widen the timeframe", "connecting a source",
                       "history is long enough", "more often", "ordinary state",
                       "usual answer", "nothing to hold up"]
        for placeholder in everyPlaceholder {
            XCTAssertTrue(placeholder.detail.hasSuffix("."), placeholder.detail)
            XCTAssertGreaterThan(placeholder.detail.count, 60, placeholder.detail)
            XCTAssertTrue(escapes.contains { placeholder.detail.lowercased().contains($0) },
                          "no route out of the empty state: \(placeholder.detail)")
        }
    }

    /// This copy reaches SwiftUI as a `String` variable, not a literal, so
    /// `Text` takes the `StringProtocol` overload and never parses markdown.
    /// An asterisk written for emphasis renders as an asterisk on the card.
    func testNoCopyRelyingOnMarkdownThatWillNeverBeParsed() {
        for placeholder in everyPlaceholder {
            for text in [placeholder.headline, placeholder.detail] {
                for marker in ["*", "_", "`", "](", "##"] {
                    XCTAssertFalse(text.contains(marker),
                                   "markdown '\(marker)' will render literally: \(text)")
                }
            }
        }
    }

    /// Two different reasons within one section must never produce the same
    /// words, or the section is back to being an absence that means nothing in
    /// particular — which is the state this whole type replaced.
    ///
    /// Across the two sections the wording deliberately *does* repeat where the
    /// fact repeats (nothing is recording; the overlap is short), so the check
    /// is per section rather than over the union.
    func testEachSectionsReasonsAreDistinguishableFromEachOther() {
        for reasons in [patternReasons, leadReasons] {
            let headlines = reasons.map(\.headline)
            XCTAssertEqual(Set(headlines).count, headlines.count,
                           headlines.joined(separator: " | "))
            let details = reasons.map(\.detail)
            XCTAssertEqual(Set(details).count, details.count)
        }
    }
}
