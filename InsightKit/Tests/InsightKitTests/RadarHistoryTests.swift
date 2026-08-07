import XCTest
@testable import InsightKit

/// **The radar's own history** — backlog `S4` (flagged days over time, and how a
/// finding builds) and `S3` (how many nights a departure has to last).
///
/// The expensive property here is not a number, it is a *shape*: the history has
/// to be the same walk the card already does, or the chart and the card can
/// disagree about the same morning. So the first test is an equivalence, not a
/// value.
final class RadarHistoryTests: XCTestCase {

    private let calendar = TestClock.utc

    private func snapshot(_ daysAgo: Int, signals: [HealthWatchModel.Signal])
        -> SymptomRadarModel.DaySnapshot {
        SymptomRadarModel.DaySnapshot(
            day: calendar.startOfDay(for: TestClock.day(daysAgo)),
            output: HealthWatchModel.output(fromEvaluated: signals))
    }

    /// A blank day — nothing worn, nothing to judge.
    private func blank(_ daysAgo: Int) -> SymptomRadarModel.DaySnapshot {
        SymptomRadarModel.DaySnapshot(
            day: calendar.startOfDay(for: TestClock.day(daysAgo)), output: nil)
    }

    private func signal(_ metric: MetricType, z: Double,
                        concerning: Bool = true) -> HealthWatchModel.Signal {
        HealthWatchModel.Signal(metric: metric, recent: 0, reference: 0, zScore: z,
                                isConcerning: concerning)
    }

    /// Two channels leaning by `z`, which is the shape the card scores.
    private func leaning(_ daysAgo: Int, z: Double) -> SymptomRadarModel.DaySnapshot {
        snapshot(daysAgo, signals: [signal(.restingHeartRate, z: z),
                                    signal(.respiratoryRate, z: z)])
    }

    // MARK: - S4

    /// **The chart cannot drift from the card.** `accumulation(over:)` is now the
    /// last row of `history(over:)`, so a change to one is a change to both —
    /// this pins that they really are the same walk, including across a day the
    /// watch could not judge.
    func testTheHistoryEndsWhereTheAccumulationDoes() {
        let timeline = [leaning(9, z: 2.0), leaning(8, z: 2.0), blank(7),
                        leaning(6, z: 2.0), leaning(5, z: 0.0), blank(4)]
        let history = SymptomRadarModel.history(over: timeline)
        XCTAssertEqual(history.count, timeline.count,
                       "a blank day still gets a row — the chart needs the gap")
        XCTAssertEqual(history.last?.accumulation,
                       SymptomRadarModel.accumulation(over: timeline))
    }

    /// A day nothing was worn carries the accumulation forward untouched. The
    /// alternative — treating it as a zero — pulls the statistic down by the
    /// allowance for every night the reader forgot something, which is a way of
    /// forgetting an illness because somebody stopped measuring it.
    func testABlankDayCarriesTheAccumulationRatherThanDecayingIt() throws {
        let history = SymptomRadarModel.history(
            over: [leaning(5, z: 2.0), leaning(4, z: 2.0), blank(3), blank(2)])
        let afterTwoIllDays = try XCTUnwrap(history.first { $0.day == history[1].day })
        XCTAssertGreaterThan(afterTwoIllDays.accumulation.statistic, 0)
        for row in history.suffix(2) {
            XCTAssertEqual(row.accumulation.statistic,
                           afterTwoIllDays.accumulation.statistic, accuracy: 1e-9)
            XCTAssertNil(row.status, "a day with nothing to judge has no verdict")
            XCTAssertFalse(row.isFlagged, "and it is certainly not a flag")
        }
    }

    /// **How it builds.** The reader's complaint was that a correct flag
    /// evaporated the next morning; the accumulation is the answer, and it has
    /// to be visibly monotone while the body stays away from normal.
    func testTheAccumulationRisesWhileTheDepartureLasts() {
        let history = SymptomRadarModel.history(
            over: (0..<6).reversed().map { leaning($0, z: 2.0) })
        let statistics = history.map(\.accumulation.statistic)
        for (earlier, later) in zip(statistics, statistics.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later, earlier)
        }
        XCTAssertGreaterThan(statistics.last ?? 0, statistics.first ?? 0)
    }

    /// One line per stretch of consecutive judged days, and never a line across
    /// a gap — a line crossing a fortnight nothing was worn asserts a trend
    /// nobody measured.
    func testRunsSplitOnAnyMissingDayAndKeepLoneDays() {
        let history = SymptomRadarModel.history(
            over: [leaning(9, z: 1.0), leaning(8, z: 1.0), blank(7),
                   leaning(6, z: 1.0), blank(5), blank(4), leaning(3, z: 1.0)])
        let runs = SymptomRadarModel.runs(of: history, calendar: calendar)
        XCTAssertEqual(runs.map(\.count), [2, 1, 1])
        XCTAssertTrue(runs.allSatisfy { $0.allSatisfy { $0.output != nil } },
                      "a blank day must never land inside a drawn line")
    }

    /// The chart's span is longer than the ledger's, deliberately: the ledger
    /// grades the card over a window short enough that last winter is not
    /// marking this spring's homework, and a chart of when the reader was ill
    /// wants a season either side of one.
    func testTheHistorySpanIsLongerThanTheLedgerWindow() {
        XCTAssertGreaterThan(SymptomRadarModel.historyDays,
                             SymptomRadarModel.ledgerDays)
    }

    // MARK: - S3: nights to flag

    /// The arithmetic the sheet renders, and nothing else in it: while the body
    /// sits `excess` past ordinary, each night adds `excess − allowance`, and the
    /// accumulation is a finding at the decision interval.
    func testNightsToFlagIsTheAccumulationsOwnArithmetic() {
        for excess in SymptomRadarModel.flagLatencyExcesses {
            let expected = Int((SymptomRadarModel.Memory.decisionInterval
                                / (excess - SymptomRadarModel.Memory.allowance)).rounded(.up))
            XCTAssertEqual(SymptomRadarModel.nightsToFlag(atDailyExcess: excess), expected,
                           "\(excess) SD")
        }
        // The figures the sheet prints today, so a change to the allowance or
        // the decision interval is visible as a change to this list rather than
        // as a silently different sheet.
        XCTAssertEqual(SymptomRadarModel.flagLatencyExcesses.map {
            SymptomRadarModel.nightsToFlag(atDailyExcess: $0)
        }, [12, 6, 4, 3])
    }

    /// **A departure at or under the allowance never accumulates**, however long
    /// it lasts, and the sheet has to be able to say "never" rather than print a
    /// large number. That is the allowance doing its job: a detector that
    /// eventually flags everything has stopped saying anything.
    func testADepartureInsideTheAllowanceNeverFlags() {
        XCTAssertNil(SymptomRadarModel.nightsToFlag(
            atDailyExcess: SymptomRadarModel.Memory.allowance))
        XCTAssertNil(SymptomRadarModel.nightsToFlag(atDailyExcess: 0.1))
        XCTAssertNil(SymptomRadarModel.nightsToFlag(atDailyExcess: 0))
    }

    /// And the latency really is reachable by the CUSUM it describes: hold a
    /// departure at the stated size for the stated number of nights and the
    /// statistic arrives at the decision interval.
    func testHoldingADepartureForThatManyNightsReachesTheDecisionInterval() throws {
        let excess = 1.5
        let nights = try XCTUnwrap(SymptomRadarModel.nightsToFlag(atDailyExcess: excess))
        var statistic = 0.0
        for _ in 0..<nights {
            statistic = Swift.min(SymptomRadarModel.Memory.accumulationCap,
                                  Swift.max(0, statistic + excess
                                              - SymptomRadarModel.Memory.allowance))
        }
        XCTAssertGreaterThanOrEqual(statistic,
                                    SymptomRadarModel.Memory.decisionInterval - 1e-9)
    }
}
