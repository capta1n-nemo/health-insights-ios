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
final class SectionPlaceholderTests: XCTestCase {

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
    private var patternReasons: [SectionPlaceholder] {
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
    private var leadReasons: [SectionPlaceholder] {
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

    /// One instance per distinct *reason* the four non-findings sections can
    /// give. Deliberately not one per parameterisation — "no readings over this
    /// window" for one input and for nine is the same reason with a different
    /// number in it, and the distinguishability check below is about reasons.
    private var otherReasons: [SectionPlaceholder] {
        [
            .scoreHistory(points: 0, isComputing: true),
            .scoreHistory(points: 0, isComputing: false),
            .scoreHistory(points: 1, isComputing: false),
            .drivers(hasScore: true),
            .drivers(hasScore: false),
            .overlay(inputCount: 0),
            .overlay(inputCount: 9),
            .periodContrast(comparable: 0),
            .periodContrast(comparable: 6)
        ]
    }

    /// The parameterised variants, swept for wording rather than for identity.
    private var everyVariant: [SectionPlaceholder] {
        everyPlaceholder + [
            .overlay(inputCount: 1),
            .periodContrast(comparable: 1)
        ]
    }

    private var everyPlaceholder: [SectionPlaceholder] {
        patternReasons + leadReasons + otherReasons
    }

    // MARK: - Score over time

    /// The one that matters. `AppModel.scoreHistory` returns `[]` on first ask
    /// and replays 90 days behind the view, so a card opened cold is empty for a
    /// second — and "no scored days yet" there is a false statement that
    /// corrects itself only after the reader has read it.
    func testAPendingReplayIsNeverReportedAsNoData() {
        let computing = SectionPlaceholder.scoreHistory(points: 0, isComputing: true)
        XCTAssertTrue(computing.headline.lowercased().contains("working out"),
                      computing.headline)
        XCTAssertFalse(computing.detail.lowercased().contains("no scored"))
        XCTAssertNotEqual(computing, .scoreHistory(points: 0, isComputing: false))
    }

    /// One point and none are different waits — one more qualifying day versus
    /// a first one — and the floor is quoted from `ScoreHistory` rather than
    /// written out, so the number cannot drift from the rule.
    func testTheScoreFloorIsQuotedFromTheTypeThatEnforcesIt() {
        let none = SectionPlaceholder.scoreHistory(points: 0, isComputing: false)
        let one = SectionPlaceholder.scoreHistory(points: 1, isComputing: false)
        XCTAssertNotEqual(none.headline, one.headline)
        XCTAssertTrue(one.headline.lowercased().contains("one scored day"), one.headline)
        for text in [none.detail, one.detail] {
            XCTAssertTrue(text.contains("\(ScoreHistory.minimumContributors) "), text)
        }
    }

    // MARK: - The other two

    /// "This card reads nine things and none recorded" is a different message
    /// from "this card reads nothing", and only the first is about your data.
    func testTheOverlayNamesHowManyInputsTheCardActuallyDeclares() {
        let nine = SectionPlaceholder.overlay(inputCount: 9)
        XCTAssertTrue(nine.detail.contains("9 signals"), nine.detail)
        XCTAssertTrue(nine.detail.lowercased().contains("widening"), nine.detail)

        let one = SectionPlaceholder.overlay(inputCount: 1)
        XCTAssertTrue(one.detail.contains("1 signal,"), one.detail)
        XCTAssertFalse(one.detail.contains("1 signals"), one.detail)

        // A card declaring nothing is a gap in the app, and says so rather than
        // implying the reader could fix it by recording more.
        let none = SectionPlaceholder.overlay(inputCount: 0)
        XCTAssertTrue(none.detail.lowercased().contains("gap in the app"), none.detail)
    }

    /// Not enough history versus enough history and nothing moved — "wait" and
    /// "you're steady" are opposite messages and the section used to give
    /// neither.
    func testPeriodContrastSeparatesNotEnoughHistoryFromNothingMoved() {
        let waiting = SectionPlaceholder.periodContrast(comparable: 0)
        XCTAssertTrue(waiting.headline.lowercased().contains("not enough history"),
                      waiting.headline)
        XCTAssertTrue(waiting.detail.contains("\(PeriodContrast.windowDays) days"),
                      waiting.detail)
        XCTAssertTrue(waiting.detail.contains("\(PeriodContrast.minimumDaysPerPeriod) days"),
                      waiting.detail)

        let steady = SectionPlaceholder.periodContrast(comparable: 6)
        XCTAssertTrue(steady.headline.lowercased().contains("hasn't moved"), steady.headline)
        XCTAssertTrue(steady.detail.contains("6 signals"), steady.detail)
        XCTAssertFalse(steady.detail.lowercased().contains("not enough"))
    }

    /// A card with no number and a card whose number nothing explains are
    /// different situations, and the first one has something the reader can do.
    func testDriversSeparateNoNumberFromNothingStandingOut() {
        let scoreless = SectionPlaceholder.drivers(hasScore: false)
        let scored = SectionPlaceholder.drivers(hasScore: true)
        XCTAssertNotEqual(scoreless, scored)
        XCTAssertTrue(scoreless.headline.lowercased().contains("no number"), scoreless.headline)
        XCTAssertTrue(scored.detail.lowercased().contains("ordinary day"), scored.detail)
    }

    // MARK: - Patterns: the three reasons are not interchangeable

    func testNoSeriesSaysNothingIsRecordingRatherThanNothingIsWrong() {
        let empty = SectionPlaceholder.patterns(series: [], score: [],
                                                 calendar: placeholderCalendar)
        XCTAssertEqual(empty, SectionPlaceholder.nothingRecording)
        XCTAssertTrue(empty.headline.lowercased().contains("nothing recording"))
        // Must not read as reassurance: no data is not the same as no problem.
        XCTAssertFalse(empty.detail.lowercased().contains("ordinary state"))
    }

    /// A card drawing one signal with no score history has no *pair*, which is a
    /// different answer from "we looked and found nothing".
    func testOneSignalAndNoScoreSaysThereIsNothingToCompareItWith() {
        let one = SectionPlaceholder.patterns(
            series: [series(.sleepDurationHours, days: 40)], score: [],
            calendar: placeholderCalendar)
        XCTAssertTrue(one.headline.lowercased().contains("one signal"), one.headline)
    }

    /// Two readings of one measurement are not a pair — the same guard
    /// `PatternFinder` applies, so the placeholder cannot claim a pair the
    /// finder would have refused to look at.
    func testTwoReadingsOfOneMeasurementDoNotCountAsAPair() {
        let sameBasis = SectionPlaceholder.patterns(
            series: [series(.heartRateVariabilityRMSSD, days: 40),
                     series(.heartRateVariabilitySDNN, days: 40)],
            score: [], calendar: placeholderCalendar)
        XCTAssertTrue(sameBasis.headline.lowercased().contains("one signal"),
                      sameBasis.headline)
    }

    /// The defect this whole type exists to avoid: telling a reader nothing
    /// stood out when in truth nothing was looked at.
    func testAShortOverlapIsReportedAsAShortOverlapAndQuotesIt() {
        let short = SectionPlaceholder.patterns(
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
        let one = SectionPlaceholder.patterns(
            series: [series(.sleepDurationHours, days: 1),
                     series(.oxygenSaturation, days: 1)],
            score: [], calendar: placeholderCalendar)
        XCTAssertTrue(one.detail.contains("1 day."), one.detail)
        XCTAssertFalse(one.detail.contains("1 days"), one.detail)
    }

    /// And the reassuring case, which the vanishing section never gave anyone:
    /// enough days, nothing moving together, and that is fine.
    func testEnoughDaysWithNothingMovingTogetherSaysSoOutLoud() {
        let plenty = SectionPlaceholder.patterns(
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
        let short = SectionPlaceholder.leads(
            series: [series(.sleepDurationHours, days: 40)], score: score(days: 6),
            calendar: placeholderCalendar)
        XCTAssertTrue(short.headline.lowercased().contains("score history"), short.headline)
        XCTAssertTrue(short.detail.contains("are 6"), short.detail)
        XCTAssertTrue(short.detail.contains("\(PatternFinder.defaultMinimumPairs) days"),
                      short.detail)
    }

    func testOneDayOfScoreHistoryReadsAsSingular() {
        let one = SectionPlaceholder.leads(
            series: [series(.sleepDurationHours, days: 40)], score: score(days: 1),
            calendar: placeholderCalendar)
        XCTAssertTrue(one.detail.contains("is 1 so far"), one.detail)
    }

    /// Plenty of score history but a signal recorded on almost none of those
    /// days is a *third* reason, and blaming the score history would send the
    /// reader to wait for something they already have.
    func testALongScoreHistoryWithASparseSignalBlamesTheOverlapNotTheHistory() {
        let sparse = SectionPlaceholder.leads(
            series: [series(.sleepDurationHours, days: 4)], score: score(days: 40),
            calendar: placeholderCalendar)
        XCTAssertTrue(sparse.headline.lowercased().contains("overlapping"), sparse.headline)
        XCTAssertTrue(sparse.detail.contains("40 days behind it"), sparse.detail)
        XCTAssertTrue(sparse.detail.contains("at most 4"), sparse.detail)
    }

    func testEnoughOfEverythingAndNoLeadSaysThatIsTheUsualAnswer() {
        let plenty = SectionPlaceholder.leads(
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
        for placeholder in everyVariant {
            XCTAssertFalse(placeholder.headline.isEmpty)
            XCTAssertLessThanOrEqual(placeholder.headline.count, 44, placeholder.headline)
            XCTAssertFalse(placeholder.headline.hasSuffix("."), placeholder.headline)
            XCTAssertEqual(placeholder.headline.first?.isUppercase, true,
                           placeholder.headline)
        }
    }

    /// Every empty state does one of exactly two jobs: name the condition that
    /// would fill it, or say plainly that empty is the right answer. "Check back
    /// later" with neither is the failure mode this whole type exists to avoid,
    /// and it is what the sections did by simply not being there.
    func testEveryDetailEitherNamesItsConditionOrSaysEmptyIsFine() {
        let namesACondition = [
            "keep recording", "widen the timeframe", "widening", "connecting a source",
            "history is long enough", "more often", "nothing to hold up",
            "as soon as", "waiting for", "cleared that yet", "sections below"
        ]
        let saysEmptyIsFine = [
            "ordinary state", "usual answer", "ordinary day", "good answer",
            "gap in the app"
        ]
        for placeholder in everyVariant {
            let text = placeholder.detail.lowercased()
            XCTAssertTrue(placeholder.detail.hasSuffix("."), placeholder.detail)
            XCTAssertGreaterThan(placeholder.detail.count, 60, placeholder.detail)
            XCTAssertTrue(
                namesACondition.contains { text.contains($0) }
                    || saysEmptyIsFine.contains { text.contains($0) },
                "neither a condition nor reassurance: \(placeholder.detail)")
        }
    }

    /// This copy reaches SwiftUI as a `String` variable, not a literal, so
    /// `Text` takes the `StringProtocol` overload and never parses markdown.
    /// An asterisk written for emphasis renders as an asterisk on the card.
    func testNoCopyRelyingOnMarkdownThatWillNeverBeParsed() {
        for placeholder in everyVariant {
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
        for reasons in [patternReasons, leadReasons, otherReasons] {
            let headlines = reasons.map(\.headline)
            XCTAssertEqual(Set(headlines).count, headlines.count,
                           headlines.joined(separator: " | "))
            let details = reasons.map(\.detail)
            XCTAssertEqual(Set(details).count, details.count)
        }
    }
}
