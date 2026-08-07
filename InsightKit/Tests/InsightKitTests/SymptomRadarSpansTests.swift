import XCTest
@testable import InsightKit

private let spanCalendar = TestClock.utc

/// `SymptomRadarModel.flaggedSpans` — the block a multi-day illness reads as on
/// the §B11-1 calendar.
///
/// The claim under test is the reader's ruling: a day is coloured by **its own**
/// statistic, and the accumulated episode is drawn as a **band** across the days
/// it spanned. That only works if the band is cut from the *verdict's* status
/// (today or memory, whichever said more) while the colour comes from the day's
/// own — so the discriminating test here is the carried-forward day, which must
/// land inside a span and outside an `episode`.
final class SymptomRadarSpansTests: XCTestCase {

    // MARK: - Fixtures

    /// A row with its verdict status stated outright, for the grouping rules.
    /// The arithmetic that produces a real carried day is exercised separately,
    /// through `history(over:)`, below.
    private func row(daysAgo: Int, ownScore: Double,
                     verdict: SymptomRadarStatus?) -> SymptomRadarModel.DayHistory {
        let signals = [HealthWatchModel.Signal(metric: .restingHeartRate, recent: 0,
                                               reference: 0, zScore: 0,
                                               isConcerning: false)]
        return SymptomRadarModel.DayHistory(
            day: spanCalendar.startOfDay(for: TestClock.day(daysAgo)),
            output: verdict == nil ? nil : .init(signals: signals, score: ownScore),
            accumulation: .none,
            status: verdict)
    }

    /// Four concerning channels at a chosen z, oldest-first timeline material.
    private func snapshot(daysAgo: Int, z: Double) -> SymptomRadarModel.DaySnapshot {
        let metrics: [MetricType] = [.skinTemperatureDeviation, .restingHeartRate,
                                     .respiratoryRate, .oxygenSaturation]
        let signals = metrics.map { metric in
            HealthWatchModel.Signal(metric: metric, recent: 0, reference: 0,
                                    zScore: z, isConcerning: z > 0)
        }
        // The score the *day alone* would have shown. Passed rather than
        // stipulated so `Output.status` and the verdict cannot disagree by
        // construction — the whole point of this test is where they disagree
        // for a real reason.
        return .init(day: spanCalendar.startOfDay(for: TestClock.day(daysAgo)),
                     output: .init(signals: signals,
                                   score: HealthWatchModel.score(signals)))
    }

    // MARK: - The grouping rules

    func testConsecutiveFlaggedDaysAreOneSpan() {
        let history = [row(daysAgo: 9, ownScore: 96, verdict: .quiet),
                       row(daysAgo: 8, ownScore: 60, verdict: .someSigns),
                       row(daysAgo: 7, ownScore: 40, verdict: .strongSigns),
                       row(daysAgo: 6, ownScore: 55, verdict: .someSigns),
                       row(daysAgo: 5, ownScore: 96, verdict: .quiet)]
        let spans = SymptomRadarModel.flaggedSpans(in: history, calendar: spanCalendar)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans.first?.dayCount, 3)
        XCTAssertEqual(spans.first?.days.count, 3)
        XCTAssertEqual(spans.first?.lowestDailyScore, 40)
        XCTAssertEqual(spans.first?.start,
                       spanCalendar.startOfDay(for: TestClock.day(8)))
        XCTAssertEqual(spans.first?.end,
                       spanCalendar.startOfDay(for: TestClock.day(6)))
    }

    /// Two quiet mornings inside an illness must not end the story — the same
    /// join rule `episodes` uses, and the reason it is the same rule is that
    /// two adjacent drawings of one illness that break in different places is
    /// worse than either.
    func testUpToTwoQuietDaysBridgeASpanAndThreeSplitIt() throws {
        let bridged = [row(daysAgo: 10, ownScore: 40, verdict: .strongSigns),
                       row(daysAgo: 9, ownScore: 96, verdict: .quiet),
                       row(daysAgo: 8, ownScore: 96, verdict: .quiet),
                       row(daysAgo: 7, ownScore: 45, verdict: .strongSigns)]
        let one = try XCTUnwrap(
            SymptomRadarModel.flaggedSpans(in: bridged, calendar: spanCalendar).first)
        XCTAssertEqual(SymptomRadarModel.flaggedSpans(in: bridged,
                                                      calendar: spanCalendar).count, 1)
        // Four calendar days covered, two of them flagged: the band spans what
        // it spanned, and the list of days claims only what was flagged.
        XCTAssertEqual(one.dayCount, 4)
        XCTAssertEqual(one.days.count, 2)
        // And the bridged morning is inside the band — the property the
        // calendar draws.
        XCTAssertTrue(one.contains(TestClock.day(9), calendar: spanCalendar))
        XCTAssertTrue(one.begins(on: TestClock.day(10), calendar: spanCalendar))
        XCTAssertTrue(one.ends(on: TestClock.day(7), calendar: spanCalendar))

        let split = [row(daysAgo: 10, ownScore: 40, verdict: .strongSigns),
                     row(daysAgo: 9, ownScore: 96, verdict: .quiet),
                     row(daysAgo: 8, ownScore: 96, verdict: .quiet),
                     row(daysAgo: 7, ownScore: 96, verdict: .quiet),
                     row(daysAgo: 6, ownScore: 45, verdict: .strongSigns)]
        XCTAssertEqual(SymptomRadarModel.flaggedSpans(in: split,
                                                      calendar: spanCalendar).count, 2)
    }

    /// A stretch nothing was worn is not a stretch of wellness, and it is also
    /// not a span: an unjudgeable day has no verdict, so it cannot flag.
    func testUnjudgeableDaysNeverFlag() {
        let history = [row(daysAgo: 5, ownScore: 0, verdict: nil),
                       row(daysAgo: 4, ownScore: 0, verdict: nil)]
        XCTAssertTrue(SymptomRadarModel.flaggedSpans(in: history,
                                                     calendar: spanCalendar).isEmpty)
    }

    func testNoFlagsMeansNoSpans() {
        let history = (1...5).map { row(daysAgo: $0, ownScore: 96, verdict: .quiet) }
        XCTAssertTrue(SymptomRadarModel.flaggedSpans(in: history,
                                                     calendar: spanCalendar).isEmpty)
    }

    // MARK: - The one that matters: carried-forward days

    /// **A day the card spoke on only because of memory belongs to the band and
    /// not to the episode**, and both drawings are correct.
    ///
    /// Built through the real `history(over:)` rather than stipulated, because
    /// the claim is about the CUSUM's arithmetic and a hand-set status would
    /// prove nothing about it. Three hard days push the accumulation to its cap;
    /// the mild days after them score in the nineties **on their own numbers**
    /// while the accumulation still has the card speaking. That is the reader's
    /// *"why am I now back at 99% just 1 day later?"*, and it is exactly the day
    /// the calendar must colour green-ish and still cover with a band.
    func testCarriedForwardDayIsInTheSpanButNotTheEpisode() throws {
        let timeline = [snapshot(daysAgo: 14, z: 0), snapshot(daysAgo: 13, z: 0),
                        snapshot(daysAgo: 12, z: 2.2), snapshot(daysAgo: 11, z: 2.2),
                        snapshot(daysAgo: 10, z: 2.2),
                        snapshot(daysAgo: 9, z: 0.7), snapshot(daysAgo: 8, z: 0.7),
                        snapshot(daysAgo: 7, z: 0.7),
                        snapshot(daysAgo: 6, z: 0), snapshot(daysAgo: 5, z: 0),
                        snapshot(daysAgo: 4, z: 0), snapshot(daysAgo: 3, z: 0)]
        let history = SymptomRadarModel.history(over: timeline)
        let spans = SymptomRadarModel.flaggedSpans(in: history, calendar: spanCalendar)
        let episodes = SymptomRadarModel.episodes(in: timeline, calendar: spanCalendar)

        let carried = history.filter { $0.isFlagged && $0.output?.status == .quiet }
        XCTAssertFalse(carried.isEmpty,
                       "fixture no longer produces a carried-forward day")

        // Every carried day is quiet on its own numbers — so the calendar's
        // colour, which reads `output.status`, does not paint it as illness.
        for day in carried {
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(day.dailyScore), 85)
            XCTAssertTrue(spans.contains { $0.contains(day.day, calendar: spanCalendar) },
                          "carried day \(day.day) fell outside every band")
            XCTAssertFalse(episodes.contains { $0.start <= day.day && day.day <= $0.end },
                           "carried day \(day.day) is inside an episode; "
                           + "episodes are the day's own status by design")
        }

        // One illness, one band, and it is longer than the episode under it.
        XCTAssertEqual(spans.count, 1)
        let span = try XCTUnwrap(spans.first)
        XCTAssertEqual(span.carriedDays, carried.count)
        XCTAssertGreaterThan(span.dayCount,
                             try XCTUnwrap(episodes.first.map {
                                 SymptomRadarModel.daysBetween($0.start, $0.end,
                                                               calendar: spanCalendar) + 1
                             }))
        // The band's depth is the worst *morning*, never the accumulation —
        // the accumulation cannot reach below the strong-signs edge by design.
        XCTAssertEqual(span.lowestDailyScore,
                       history.compactMap(\.dailyScore).min())
    }

    func testSpanCoveringFindsTheRightBlock() throws {
        let history = [row(daysAgo: 10, ownScore: 40, verdict: .strongSigns),
                       row(daysAgo: 9, ownScore: 45, verdict: .someSigns),
                       row(daysAgo: 3, ownScore: 42, verdict: .strongSigns)]
        let spans = SymptomRadarModel.flaggedSpans(in: history, calendar: spanCalendar)
        XCTAssertEqual(spans.count, 2)
        let hit = try XCTUnwrap(SymptomRadarModel.span(covering: TestClock.day(9),
                                                       in: spans,
                                                       calendar: spanCalendar))
        XCTAssertEqual(hit.start, spanCalendar.startOfDay(for: TestClock.day(10)))
        XCTAssertNil(SymptomRadarModel.span(covering: TestClock.day(6), in: spans,
                                            calendar: spanCalendar))
    }
}
