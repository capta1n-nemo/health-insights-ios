import XCTest
@testable import InsightKit

/// Filing a Screen Time screenshot to the right days and weeks, retrospectively.
///
/// Built from the reader's own screenshots (2026-08-02): a Week view headed
/// "Last Week's Average 14h 13m" with "Total Screen Time 99h 33m", and another
/// headed "20–27 Jul Average 9h 10m" with "Total Screen Time 64h 16m". Both were
/// taken on the same morning and describe **different weeks**, neither of them
/// the week they were imported in.
final class ScreenTimeImportTests: XCTestCase {

    /// Monday-first, UTC — the locale the screenshots were taken in draws M
    /// first, and every date here is pinned rather than read from the machine.
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2          // Monday
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// The morning both screenshots were taken: Sunday 2 August 2026.
    private var captured: Date { date(2026, 8, 2) }

    private func parse(_ text: String, capturedAt: Date? = nil) -> ScreenTimeScreenshotParser.Result {
        ScreenTimeScreenshotParser.parse(text, capturedAt: capturedAt ?? captured,
                                         calendar: calendar)
    }

    // MARK: - The bug this was built to fix

    /// **The whole point.** A screenshot taken three weeks ago and imported
    /// today must land in the week it was taken, not the week it was imported.
    ///
    /// The parser used to take a parameter called `now`, and every caller passed
    /// `Date()`.
    func testRelativeWeeksAnchorToCaptureNotImport() throws {
        let text = "Last Week's Average\n14h 13m\nTotal Screen Time 99h 33m"

        // Captured Sun 2 Aug → "last week" is Mon 20 Jul.
        let atCapture = try XCTUnwrap(parse(text).weekStart)
        XCTAssertEqual(atCapture, date(2026, 7, 20))

        // The same picture imported three weeks later must not move.
        let atImport = try XCTUnwrap(
            parse(text, capturedAt: captured).weekStart)
        XCTAssertEqual(atImport, atCapture)

        // And a screenshot genuinely taken later means a later week — proving
        // the anchor is being read at all rather than hard-coded.
        let laterCapture = try XCTUnwrap(
            parse(text, capturedAt: date(2026, 8, 23)).weekStart)
        XCTAssertEqual(laterCapture, date(2026, 8, 10))
    }

    /// A weekday named on a Day screenshot resolves backwards from capture.
    func testANamedDayResolvesFromCapture() throws {
        let result = parse("Tuesday\nTotal Screen Time\n4h 32m",
                           capturedAt: date(2026, 7, 9))   // a Thursday
        let day = try XCTUnwrap(result.date)
        XCTAssertEqual(day, date(2026, 7, 7), "the Tuesday before that Thursday")
    }

    // MARK: - Week ranges

    /// The reader's second screenshot. 20 Jul 2026 is a Monday and the average
    /// is the total ÷ 7, so the range is seven days from the 20th — whatever
    /// convention Apple's "27" follows.
    func testAnExplicitRangeIsRead() throws {
        let result = parse("20–27 Jul Average\n9h 10m\nTotal Screen Time 64h 16m")
        XCTAssertEqual(try XCTUnwrap(result.weekStart), date(2026, 7, 20))
    }

    /// The inclusive spelling of the same week has to give the same answer.
    func testAnInclusiveRangeGivesTheSameWeek() throws {
        XCTAssertEqual(try XCTUnwrap(parse("20 - 26 Jul").weekStart), date(2026, 7, 20))
        XCTAssertEqual(try XCTUnwrap(parse("Jul 20 – 26").weekStart), date(2026, 7, 20))
    }

    /// A range that is not a week is not a week. Two dates ten days apart is
    /// something this parser does not understand, and guessing would file ten
    /// days of data onto seven.
    func testANonWeekRangeIsRejected() {
        XCTAssertNil(parse("20 – 30 Jul Average\n9h 10m").weekStart)
    }

    /// December read in January is last year's December, not a date in the
    /// future. The year is never printed on this screen.
    func testAMonthThatHasNotHappenedYetRollsBackAYear() throws {
        let result = parse("28 Dec – 3 Jan", capturedAt: date(2026, 1, 15))
        XCTAssertEqual(try XCTUnwrap(result.weekStart), date(2025, 12, 28))
    }

    func testThisWeekResolvesToTheCaptureWeek() throws {
        // Captured Sun 2 Aug, Monday-first → this week began Mon 27 Jul.
        XCTAssertEqual(try XCTUnwrap(parse("This Week\nTotal 40h").weekStart),
                       date(2026, 7, 27))
    }

    // MARK: - What a week's numbers mean

    /// **A Week view relabels every total on it.** "Total Screen Time 99h 33m"
    /// is the week, and the words are identical to the Day view's — so without
    /// this the parser offers ninety-nine hours as one day's screen time.
    func testTotalScreenTimeOnAWeekViewIsNotADay() {
        let result = parse("Last Week's Average\n14h 13m\nTotal Screen Time 99h 33m")
        XCTAssertNil(result.dayTotal, "no figure on a week view is a day's total")
        XCTAssertTrue(result.readings.contains { $0.kind == .weeklyTotal && $0.minutes == 5973 })
    }

    /// The Day view is untouched by that rule.
    func testTotalScreenTimeOnADayViewIsStillADay() throws {
        let result = parse("Today\nTotal Screen Time\n4h 32m")
        XCTAssertEqual(try XCTUnwrap(result.dayTotal).minutes, 272)
    }

    /// **The Day view does not say "Total Screen Time" at all.** It heads the
    /// figure with the day, and the app told the reader to "open a single day
    /// and screenshot that" when that is precisely what they had done.
    ///
    /// Transcribed from the device, 2026-08-02.
    func testTheRealDayViewHeadingIsReadAsADaysTotal() throws {
        let result = parse("""
        Screen Time
        Show Today
        Yesterday, 2 August
        21h 1m
        M Tu W Th F Sa Su
        Productivity & Finance
        Other
        Social
        16h 15m
        2h 45m
        16m
        Updated today at 9:21am
        """, capturedAt: date(2026, 8, 3))

        let day = try XCTUnwrap(result.dayTotal)
        XCTAssertEqual(day.minutes, 1261, "21h 1m")
        XCTAssertEqual(result.date, date(2026, 8, 2), "yesterday, from a 3 Aug capture")
        XCTAssertNil(result.weekStart, "a weekday axis is not a week heading")
    }

    /// **"Show This Week" is a button, and it names the week you are not
    /// looking at.** It sits above last week's figures on the Week view, so
    /// reading it as a heading files a retrospective screenshot into the current
    /// week — the bug this whole parser exists to fix, arriving by another door.
    ///
    /// Transcribed from the reader's screenshot, where the title row reads
    /// "Screen Time    Show This Week" above "Last Week's Average".
    func testTheShowThisWeekButtonIsNotTheWeekBeingShown() throws {
        let result = parse("""
        Screen Time
        Show This Week
        Last Week's Average
        14h 13m
        Total Screen Time 99h 33m
        """)
        XCTAssertEqual(try XCTUnwrap(result.weekStart), date(2026, 7, 20),
                       "last week, not the capture week")
    }

    /// The same button on the Day view, where it reads "Show Today" above a
    /// screenshot of yesterday.
    func testTheShowTodayButtonIsNotTheDayBeingShown() throws {
        let result = parse("Screen Time\nShow Today\nYesterday, 2 August\n21h 1m",
                           capturedAt: date(2026, 8, 3))
        XCTAssertEqual(result.date, date(2026, 8, 2))
    }

    /// A weekday heading works the same way, for a day further back.
    func testAWeekdayHeadingIsADaysTotal() throws {
        let result = parse("Friday, 31 July\n7h 42m", capturedAt: date(2026, 8, 3))
        XCTAssertEqual(try XCTUnwrap(result.dayTotal).minutes, 462)
    }

    /// The category totals under the day figure must not be mistaken for it —
    /// they carry no day words, so they stay unlabelled and `dayTotal` picks the
    /// heading's figure.
    func testCategoryTotalsAreNotOfferedAsTheDay() throws {
        let result = parse("Yesterday, 2 August\n21h 1m\nProductivity & Finance\n16h 15m",
                           capturedAt: date(2026, 8, 3))
        XCTAssertEqual(try XCTUnwrap(result.dayTotal).minutes, 1261)
    }

    // MARK: - B10-1: the date printed on a Day screenshot

    /// **The defect the reader reported: the figure was right and the day was
    /// wrong.** Every date this parser produced came from `capturedAt`, and
    /// `capturedAt` comes from the image's EXIF — which an iOS screenshot very
    /// often does not carry, in which case `AddDataView` passes `Date()` and
    /// every relative phrase resolves against the *import*.
    ///
    /// But the Day view prints the date. "Yesterday, 2 August" says which day
    /// it is in words that do not depend on when the picture was taken, so read
    /// that and the whole failure mode goes away.
    func testThePrintedDateBeatsTheRelativeWord() throws {
        // Imported nearly three weeks after the screenshot, with no EXIF —
        // exactly what a screenshot picked out of the library looks like.
        let result = parse("Yesterday, 2 August\n21h 1m", capturedAt: date(2026, 8, 20))
        XCTAssertEqual(result.date, date(2026, 8, 2),
                       "the screen says 2 August; 'yesterday' resolved against the "
                       + "import would have said the 19th")
        XCTAssertEqual(try XCTUnwrap(result.dayTotal).minutes, 1261)
    }

    /// The same for a weekday heading. Resolving "Tuesday" backwards from
    /// capture can only ever land inside the last seven days, so a screenshot
    /// of any older day was filed wrong by construction.
    func testAWeekdayHeadingUsesItsPrintedDateNotTheMostRecentWeekday() {
        let result = parse("Tuesday, 5 August\n4h 32m", capturedAt: date(2026, 8, 20))
        XCTAssertEqual(result.date, date(2026, 8, 5),
                       "not the 18th, which is the Tuesday before the import")
    }

    /// A day and month with no year on the screen is the most recent one, so a
    /// December screenshot imported in January is last year's.
    func testAPrintedDateFromLastYearRollsBack() {
        let result = parse("Wednesday, 31 December\n3h", capturedAt: date(2026, 1, 5))
        XCTAssertEqual(result.date, date(2025, 12, 31))
    }

    /// A relative heading with no date printed still resolves against capture —
    /// the fallback has to survive, because "Today" alone is all some crops say.
    func testABareRelativeHeadingStillResolvesAgainstCapture() {
        XCTAssertEqual(parse("Yesterday\n21h 1m", capturedAt: date(2026, 8, 20)).date,
                       date(2026, 8, 19))
    }

    /// **A duration's digits are not dates.** OCR sometimes puts the heading and
    /// the figure on one line, and "Yesterday, 2 August 8h 1m" then offered
    /// 2 and 8 to the week-range reader, which is a six-day span — so a single
    /// day was filed as the week of 2–8 August and its total relabelled as a
    /// week's.
    func testADurationOnTheHeadingLineIsNotAWeekRange() throws {
        let result = parse("Yesterday, 2 August 8h 1m", capturedAt: date(2026, 8, 3))
        XCTAssertNil(result.weekStart, "one day is not a range")
        XCTAssertEqual(result.date, date(2026, 8, 2))
        XCTAssertEqual(try XCTUnwrap(result.dayTotal).minutes, 481)
    }

    /// **"Updated today at 9:04 am" is a refresh time, not a heading.** It is on
    /// every Screen Time screenshot, so a crop that loses the heading leaves it
    /// as the only line naming a day — and the figures then file themselves onto
    /// the day the screenshot was imported, which is the whole class B10-1 is.
    func testTheUpdatedFooterIsNotTheDayBeingShown() {
        let result = parse("21h 1m\nUpdated today at 9:04 am", capturedAt: date(2026, 8, 20))
        XCTAssertNil(result.date, "no day was named on that crop, and saying so is the answer")
    }

    /// A week wins over a day: the weekday letters down a Week chart's axis
    /// (M Tu W Th F Sa Su) will resolve, and filing a week onto one Tuesday is
    /// the worst available outcome.
    func testAWeekBeatsAWeekdayLetterFromTheAxis() {
        let result = parse("20–27 Jul Average\n9h 10m\nM Tu W Th F Sa Su\nMonday")
        guard case let .week(start) = result.period else {
            return XCTFail("expected a week, got \(String(describing: result.period))")
        }
        XCTAssertEqual(start, date(2026, 7, 20))
    }

    // MARK: - Splitting a week across its days

    /// The guarantee: however rough the bar measurement, the week still sums to
    /// the exact total that was printed on the screen.
    func testTheSplitPreservesTheWeeklyTotalExactly() throws {
        let total = 5973.0                                  // 99h 33m
        let bars = [3.0, 5.5, 5.0, 7.5, 9.0, 9.5, 13.0]     // the reader's shape
        let days = try XCTUnwrap(ScreenTimeWeekBreakdown.split(
            weekStart: date(2026, 7, 20), totalMinutes: total,
            barHeights: bars, calendar: calendar))
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.minutes).reduce(0, +), total, accuracy: 0.0001)
    }

    /// Proportions are respected: the tallest bar gets the most minutes.
    func testTheSplitFollowsTheBarHeights() throws {
        let days = try XCTUnwrap(ScreenTimeWeekBreakdown.split(
            weekStart: date(2026, 7, 20), totalMinutes: 700,
            barHeights: [1, 1, 1, 1, 1, 1, 8], calendar: calendar))
        XCTAssertEqual(days.last?.minutes ?? 0, 400, accuracy: 1)
        XCTAssertEqual(days.first?.minutes ?? 0, 50, accuracy: 1)
    }

    /// Days run from the week's first day, in order.
    func testTheSplitDatesTheDaysFromTheWeekStart() throws {
        let days = try XCTUnwrap(ScreenTimeWeekBreakdown.split(
            weekStart: date(2026, 7, 20), totalMinutes: 700,
            barHeights: Array(repeating: 1, count: 7), calendar: calendar))
        XCTAssertEqual(days.first?.date, date(2026, 7, 20))
        XCTAssertEqual(days.last?.date, date(2026, 7, 26))
    }

    /// A day with no screen time is a real answer and keeps its place.
    func testAZeroBarIsADayWithNoScreenTime() throws {
        let days = try XCTUnwrap(ScreenTimeWeekBreakdown.split(
            weekStart: date(2026, 7, 20), totalMinutes: 600,
            barHeights: [0, 1, 1, 1, 1, 1, 1], calendar: calendar))
        XCTAssertEqual(days.first?.minutes, 0)
        XCTAssertEqual(days.map(\.minutes).reduce(0, +), 600, accuracy: 0.0001)
    }

    /// **Nil, not a flat fill.** If the bars could not be measured, the honest
    /// outcome is a week with no days — not seven identical ones asserting a
    /// flatness the chart contradicts.
    func testUnmeasurableBarsProduceNoDaysAtAll() {
        let start = date(2026, 7, 20)
        XCTAssertNil(ScreenTimeWeekBreakdown.split(weekStart: start, totalMinutes: 700,
                                                   barHeights: [], calendar: calendar))
        XCTAssertNil(ScreenTimeWeekBreakdown.split(weekStart: start, totalMinutes: 700,
                                                   barHeights: Array(repeating: 0, count: 7),
                                                   calendar: calendar))
        XCTAssertNil(ScreenTimeWeekBreakdown.split(weekStart: start, totalMinutes: 700,
                                                   barHeights: [1, 2, 3], calendar: calendar))
    }

    // MARK: - Precedence

    private func entry(_ provenance: ScreenTimeProvenance, minutes: Double,
                       recordedAt: Date) -> ScreenTimeEntry {
        ScreenTimeEntry(day: date(2026, 7, 21), minutes: minutes,
                        provenance: provenance, recordedAt: recordedAt)
    }

    /// "The screenshot is actual me — manual is manual."
    func testAScreenshotBeatsAnEarlierManualEntry() {
        let winner = ScreenTimePrecedence.winner(among: [
            entry(.manual, minutes: 120, recordedAt: date(2026, 7, 22)),
            entry(.dayExact, minutes: 272, recordedAt: date(2026, 8, 2))
        ])
        XCTAssertEqual(winner?.provenance, .dayExact)
        XCTAssertEqual(winner?.minutes, 272)
    }

    /// "…unless I manually override over the top of it again."
    func testAManualEntryMadeAfterTheImportWins() {
        let winner = ScreenTimePrecedence.winner(among: [
            entry(.dayExact, minutes: 272, recordedAt: date(2026, 8, 2)),
            entry(.manual, minutes: 300, recordedAt: date(2026, 8, 3))
        ])
        XCTAssertEqual(winner?.provenance, .manual)
        XCTAssertEqual(winner?.minutes, 300)
    }

    /// A screenshot older than the manual entry still loses — authority does not
    /// rescue it, because the reader corrected the app after seeing it.
    func testAuthorityDoesNotOverrideADeliberateCorrection() {
        let winner = ScreenTimePrecedence.winner(among: [
            entry(.weekEstimate, minutes: 200, recordedAt: date(2026, 8, 1)),
            entry(.dayExact, minutes: 272, recordedAt: date(2026, 8, 1)),
            entry(.manual, minutes: 300, recordedAt: date(2026, 8, 5))
        ])
        XCTAssertEqual(winner?.provenance, .manual)
    }

    /// **An exact day is never clobbered by a week estimate, even a newer one.**
    /// Re-importing an old week screenshot must not degrade a day the reader
    /// screenshotted precisely.
    func testAnExactDayOutranksALaterWeekEstimate() {
        let winner = ScreenTimePrecedence.winner(among: [
            entry(.dayExact, minutes: 272, recordedAt: date(2026, 8, 1)),
            entry(.weekEstimate, minutes: 200, recordedAt: date(2026, 8, 9))
        ])
        XCTAssertEqual(winner?.provenance, .dayExact)
        XCTAssertEqual(winner?.minutes, 272)
    }

    /// Re-importing the same week screenshot replaces its own estimate rather
    /// than piling up beside it.
    func testANewerWeekEstimateReplacesAnOlderOne() {
        let winner = ScreenTimePrecedence.winner(among: [
            entry(.weekEstimate, minutes: 200, recordedAt: date(2026, 8, 1)),
            entry(.weekEstimate, minutes: 210, recordedAt: date(2026, 8, 9))
        ])
        XCTAssertEqual(winner?.minutes, 210)
    }

    func testNothingInNothingOut() {
        XCTAssertNil(ScreenTimePrecedence.winner(among: []))
    }

    /// The importer's own question: is this row worth writing at all?
    func testWouldWinMatchesTheResolver() {
        let existing = [entry(.dayExact, minutes: 272, recordedAt: date(2026, 8, 1))]
        XCTAssertFalse(ScreenTimePrecedence.wouldWin(
            entry(.weekEstimate, minutes: 200, recordedAt: date(2026, 8, 9)), over: existing))
        XCTAssertTrue(ScreenTimePrecedence.wouldWin(
            entry(.manual, minutes: 300, recordedAt: date(2026, 8, 9)), over: existing))
    }

    /// Estimated and exact must stay tellable apart on every surface.
    func testOnlyTheWeekSplitCallsItselfAnEstimate() {
        XCTAssertTrue(ScreenTimeProvenance.weekEstimate.isEstimate)
        XCTAssertFalse(ScreenTimeProvenance.dayExact.isEstimate)
        XCTAssertFalse(ScreenTimeProvenance.manual.isEstimate)
    }
    // MARK: - Re-importing the same day

    private func day(_ minutes: Double, _ prov: ScreenTimeProvenance,
                     recordedAt: Date) -> ScreenTimeEntry {
        ScreenTimeEntry(day: TestClock.now, minutes: minutes,
                        provenance: prov, recordedAt: recordedAt)
    }

    /// **Screen time only accumulates within a day.** A screenshot captured at
    /// 23:00 shows the whole day; one captured at noon shows half of it. Which
    /// was *imported* first says nothing about which was *captured* later, so
    /// the larger figure wins between two exact readings of the same day.
    func testLaterInTheDayWinsEvenWhenImportedFirst() {
        let complete = day(1260, .dayExact, recordedAt: TestClock.now)
        let partial = day(400, .dayExact,
                          recordedAt: TestClock.now.addingTimeInterval(3600))
        XCTAssertEqual(ScreenTimePrecedence.winner(among: [complete, partial]),
                       complete,
                       "the partial midday capture was imported later and must not win")
    }

    /// The reader's third case: incremental re-uploads of the same day, each
    /// with a higher figure. Every one of them should take.
    func testIncrementalReuploadsOfOneDayClimb() {
        var seen: [ScreenTimeEntry] = []
        for (i, m) in [200.0, 480.0, 1_010.0].enumerated() {
            let e = day(m, .dayExact,
                        recordedAt: TestClock.now.addingTimeInterval(Double(i) * 3600))
            XCTAssertTrue(ScreenTimePrecedence.wouldWin(e, over: seen),
                          "a higher figure for the same day must take")
            seen.append(e)
        }
        XCTAssertEqual(ScreenTimePrecedence.winner(among: seen)?.minutes, 1_010)
    }

    /// A week estimate is a **share** of a total, not an accumulation, so the
    /// larger-wins rule must not reach it — a fuller week re-uploaded later
    /// wins on when it was recorded, and may legitimately lower a day.
    func testWeekEstimateStillResolvesByRecency() {
        let first = day(900, .weekEstimate, recordedAt: TestClock.now)
        let refined = day(300, .weekEstimate,
                          recordedAt: TestClock.now.addingTimeInterval(3600))
        XCTAssertEqual(ScreenTimePrecedence.winner(among: [first, refined]), refined)
    }

    /// An exact day still beats a bigger week estimate — authority first, and
    /// the accumulation rule must not have overtaken it.
    func testExactDayStillBeatsALargerWeekEstimate() {
        let estimate = day(1_200, .weekEstimate,
                           recordedAt: TestClock.now.addingTimeInterval(7200))
        let exact = day(300, .dayExact, recordedAt: TestClock.now)
        XCTAssertEqual(ScreenTimePrecedence.winner(among: [estimate, exact]), exact)
    }

    /// And the reader correcting the app by hand, afterwards, still wins —
    /// even with a smaller number. Their word beats the device's accounting
    /// when it is the more recent act.
    func testAManualCorrectionAfterwardsStillWins() {
        let exact = day(1_260, .dayExact, recordedAt: TestClock.now)
        let correction = day(120, .manual,
                             recordedAt: TestClock.now.addingTimeInterval(3600))
        XCTAssertEqual(ScreenTimePrecedence.winner(among: [exact, correction]),
                       correction)
    }
}
